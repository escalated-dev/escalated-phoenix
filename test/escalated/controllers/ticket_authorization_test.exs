defmodule Escalated.Controllers.TicketAuthorizationTest do
  @moduledoc """
  Who may read and change a ticket, checked through a real router.

  The customer area and the JSON API both look a ticket up by the reference
  (or numeric id) in the URL. Nothing about that lookup ties the ticket to the
  caller, so the check has to happen on the request path -- which is why these
  requests go through `Escalated.Test.Router` instead of calling controller
  functions, where a missing pipeline is invisible.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  require Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Escalated.HostTestRepo
  alias Escalated.Schemas.{Reply, Ticket}
  alias Escalated.Services.TicketService
  alias Escalated.Test.{HostUser, Router}

  @customer_one %{id: 101}
  @customer_two %{id: 202}
  @agent %{id: 900, is_agent: true}

  defp repo, do: Escalated.repo()

  setup do
    # Ticket pages resolve the requester's name through the host user schema,
    # which lives on the host's own repo -- configured here the way a host
    # configures it, so a page renders instead of raising on missing config.
    :ok = Sandbox.checkout(HostTestRepo)
    Sandbox.mode(HostTestRepo, {:shared, self()})

    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))

    on_exit(fn ->
      Enum.each(
        [:user_repo, :user_schema, :agent_check, :api_token_validator],
        &Application.delete_env(:escalated, &1)
      )

      Sandbox.checkin(HostTestRepo)
    end)

    :ok
  end

  defp ticket_for!(customer, subject) do
    {:ok, ticket} =
      TicketService.create(%{
        subject: subject,
        description: "Body",
        requester_id: customer.id,
        requester_type: "user"
      })

    ticket
  end

  # A customer-area visit, sent the way Inertia sends one. The version header
  # has to match what Inertia.Plug computes, or a GET is answered with a 409.
  defp visit(method, path, user, body \\ nil) do
    method
    |> build(path, body)
    |> maybe_assign_user(user)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> Router.call(Router.init([]))
  end

  # A JSON API call. `headers` carries a bearer token when a test needs one.
  defp api(method, path, user, body \\ nil, headers \\ []) do
    conn = build(method, path, body)

    headers
    |> Enum.reduce(conn, fn {key, value}, acc -> put_req_header(acc, key, value) end)
    |> maybe_assign_user(user)
    |> put_req_header("accept", "application/json")
    |> Router.call(Router.init([]))
  end

  defp build(method, path, nil), do: method |> conn(path) |> init_test_session(%{})

  defp build(method, path, body) do
    method
    |> conn(path, Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> init_test_session(%{})
  end

  defp maybe_assign_user(conn, nil), do: conn
  defp maybe_assign_user(conn, user), do: assign(conn, :current_user, user)

  defp inertia_version do
    conn(:get, "/")
    |> init_test_session(%{})
    |> Inertia.Plug.call(Inertia.Plug.init([]))
    |> Map.fetch!(:private)
    |> Map.fetch!(:inertia_version)
    |> to_string()
  end

  defp replies_on(ticket) do
    repo().all(Ecto.Query.from(r in Reply, where: r.ticket_id == ^ticket.id))
  end

  describe "customer ticket list" do
    test "lists only the signed-in customer's tickets" do
      mine = ticket_for!(@customer_one, "Mine")
      theirs = ticket_for!(@customer_two, "Theirs")

      conn = visit(:get, "/support/tickets", @customer_one)

      assert conn.status == 200
      listed = Jason.decode!(conn.resp_body)["props"]["tickets"]["data"]
      assert Enum.map(listed, & &1["reference"]) == [mine.reference]
      refute conn.resp_body =~ theirs.reference
    end
  end

  describe "customer ticket page" do
    test "another customer cannot read a ticket by reference" do
      ticket = ticket_for!(@customer_one, "Private subject")

      conn = visit(:get, "/support/tickets/#{ticket.reference}", @customer_two)

      assert conn.status == 403
      refute conn.resp_body =~ "Private subject"
    end

    test "another customer cannot read a ticket by numeric id" do
      ticket = ticket_for!(@customer_one, "Private subject")

      conn = visit(:get, "/support/tickets/#{ticket.id}", @customer_two)

      assert conn.status == 403
      refute conn.resp_body =~ "Private subject"
    end

    test "another customer cannot reply to a ticket by reference" do
      ticket = ticket_for!(@customer_one, "Private")

      conn =
        visit(:post, "/support/tickets/#{ticket.reference}/reply", @customer_two, %{
          "body" => "Not my ticket"
        })

      assert conn.status == 403
      assert replies_on(ticket) == []
    end

    test "another customer cannot reply to a ticket by numeric id" do
      ticket = ticket_for!(@customer_one, "Private")

      conn =
        visit(:post, "/support/tickets/#{ticket.id}/reply", @customer_two, %{
          "body" => "Not my ticket"
        })

      assert conn.status == 403
      assert replies_on(ticket) == []
    end

    test "the requester can still read and reply to their own ticket" do
      ticket = ticket_for!(@customer_one, "My subject")

      show = visit(:get, "/support/tickets/#{ticket.reference}", @customer_one)
      assert show.status == 200
      assert Jason.decode!(show.resp_body)["props"]["ticket"]["reference"] == ticket.reference

      reply =
        visit(:post, "/support/tickets/#{ticket.reference}/reply", @customer_one, %{
          "body" => "Following up"
        })

      assert reply.status == 302
      assert [%Reply{body: "Following up"}] = replies_on(ticket)
    end
  end

  describe "JSON ticket API" do
    test "an unauthenticated ticket list is refused" do
      ticket_for!(@customer_one, "Private subject")

      conn = api(:get, "/support/api/v1/tickets", nil)

      assert conn.status == 401
      refute conn.resp_body =~ "Private subject"
    end

    test "an unauthenticated ticket read is refused" do
      ticket = ticket_for!(@customer_one, "Private subject")

      conn = api(:get, "/support/api/v1/tickets/#{ticket.reference}", nil)

      assert conn.status == 401
      refute conn.resp_body =~ "Private subject"
    end

    test "an unauthenticated status change is refused and leaves the ticket unchanged" do
      ticket = ticket_for!(@customer_one, "Private")

      conn =
        api(:patch, "/support/api/v1/tickets/#{ticket.reference}/status", nil, %{
          "status" => "closed"
        })

      assert conn.status == 401
      assert repo().get!(Ticket, ticket.id).status == "open"
    end

    test "a signed-in user who is not an agent is refused" do
      ticket = ticket_for!(@customer_one, "Private")

      list = api(:get, "/support/api/v1/tickets", @customer_one)
      assert list.status == 403

      change =
        api(:patch, "/support/api/v1/tickets/#{ticket.reference}/status", @customer_one, %{
          "status" => "closed"
        })

      assert change.status == 403
      assert repo().get!(Ticket, ticket.id).status == "open"
    end

    test "an agent signed in by the host pipeline can use the API" do
      ticket = ticket_for!(@customer_one, "Visible to agents")

      conn = api(:get, "/support/api/v1/tickets", @agent)

      assert conn.status == 200
      listed = Jason.decode!(conn.resp_body)["data"]
      assert ticket.reference in Enum.map(listed, & &1["reference"])
    end

    test "a bearer token is resolved through the host's api_token_validator" do
      Application.put_env(:escalated, :api_token_validator, fn
        "agent-token" -> {:ok, @agent}
        _other -> :error
      end)

      ticket = ticket_for!(@customer_one, "Visible to agents")

      accepted =
        api(:get, "/support/api/v1/tickets/#{ticket.reference}", nil, nil, [
          {"authorization", "Bearer agent-token"}
        ])

      assert accepted.status == 200

      rejected =
        api(:get, "/support/api/v1/tickets/#{ticket.reference}", nil, nil, [
          {"authorization", "Bearer forged-token"}
        ])

      assert rejected.status == 401
    end

    test "the public auth endpoints stay reachable without a user" do
      conn = api(:post, "/support/api/v1/auth/login", nil, %{"email" => "a@example.com"})

      # 501: no host authenticator is configured. Not 401 -- login cannot
      # require the login it exists to perform.
      assert conn.status == 501
    end
  end
end
