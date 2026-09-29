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
  alias Escalated.Schemas.{Attachment, Contact, Reply, SatisfactionRating, Ticket}
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
    test "does not include internal-note attachment metadata in the customer page" do
      ticket = ticket_for!(@customer_one, "Mine")
      {:ok, note} = TicketService.reply(ticket, %{body: "Private note", is_internal: true})

      repo().insert!(
        Attachment.changeset(%Attachment{}, %{
          ticket_id: ticket.id,
          reply_id: note.id,
          original_filename: "internal-cost-breakdown.txt",
          storage_key: "private.txt"
        })
      )

      response = visit(:get, "/support/tickets/#{ticket.reference}", @customer_one)
      assert response.status == 200
      refute response.resp_body =~ "internal-cost-breakdown"
      assert Jason.decode!(response.resp_body)["props"]["ticket"]["attachments"] == []
    end

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
    test "reply attribution comes from the authenticated agent" do
      ticket = ticket_for!(@customer_one, "Support")

      conn =
        api(:post, "/support/api/v1/tickets/#{ticket.reference}/reply", @agent, %{
          "body" => "Agent reply",
          "author_id" => @customer_two.id,
          "is_internal" => true
        })

      assert conn.status == 201
      assert [%Reply{author_id: 900, is_internal: true}] = replies_on(ticket)
    end

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

    test "default authorization rejects customer sessions and bearer tokens before mutations" do
      Application.delete_env(:escalated, :agent_check)
      Application.put_env(:escalated, :api_token_validator, fn _ -> {:ok, @customer_one} end)
      ticket = ticket_for!(@customer_one, "Private")
      assert api(:get, "/support/api/v1/tickets", @customer_one).status == 403

      conn =
        api(
          :patch,
          "/support/api/v1/tickets/#{ticket.reference}/status",
          nil,
          %{"status" => "closed"},
          [{"authorization", "Bearer customer-token"}]
        )

      assert conn.status == 403
      assert repo().get!(Ticket, ticket.id).status == "open"
      assert api(:get, "/support/api/v1/tickets", @agent).status == 200
    end

    test "the public auth endpoints stay reachable without a user" do
      conn = api(:post, "/support/api/v1/auth/login", nil, %{"email" => "a@example.com"})

      # 501: no host authenticator is configured. Not 401 -- login cannot
      # require the login it exists to perform.
      assert conn.status == 501
    end
  end

  describe "customer ticket creation" do
    test "requires an identified user before writing anything" do
      for user <- [nil, %{}, %{id: nil}, %{id: ""}, %{id: false}] do
        response =
          api(:post, "/support/tickets", user, %{
            "ticket" => %{
              "subject" => "Help",
              "description" => "Details",
              "guest_email" => "guest@example.com"
            }
          })

        assert response.status == 401
      end

      assert repo().aggregate(Ticket, :count) == 0
      assert repo().aggregate(Contact, :count) == 0
    end

    test "keeps customer fields and derives ownership while staff fields retain server defaults" do
      response =
        api(:post, "/support/tickets", @customer_one, %{
          "ticket" => %{
            "subject" => "Delivery",
            "description" => "Please help",
            "priority" => "high",
            "ticket_type" => "question",
            "requester_id" => @customer_two.id,
            "requester_type" => "OtherUser",
            "status" => "closed",
            "assigned_to" => @agent.id,
            "contact_id" => 999,
            "guest_email" => "other@example.com",
            "guest_name" => "Other",
            "guest_token" => "supplied",
            "channel" => "chat",
            "metadata" => %{"admin" => true},
            "sla_breached" => true,
            "closed_at" => "2030-01-01T00:00:00Z",
            "snoozed_by" => @agent.id
          }
        })

      assert response.status == 302
      ticket = repo().one!(Ticket)
      assert ticket.subject == "Delivery"
      assert ticket.priority == "high"
      assert ticket.ticket_type == "question"
      assert ticket.requester_id == @customer_one.id
      assert ticket.requester_type == to_string(HostUser)
      assert ticket.status == "open"
      assert is_nil(ticket.assigned_to)
      assert is_nil(ticket.contact_id)
      assert is_nil(ticket.guest_email)
      assert is_nil(ticket.guest_token)
      assert is_nil(ticket.channel)
      assert ticket.metadata == %{}
      refute ticket.sla_breached
      assert is_nil(ticket.closed_at)
      assert is_nil(ticket.snoozed_by)
      assert repo().aggregate(Contact, :count) == 0
    end

    test "returns a field error for a malformed ticket payload" do
      assert api(:post, "/support/tickets", @customer_one, %{"ticket" => "invalid"}).status == 422
      assert repo().aggregate(Ticket, :count) == 0
    end
  end

  describe "customer satisfaction" do
    test "only the requester can consume a ticket rating" do
      ticket = ticket_for!(@customer_one, "Resolved")
      repo().update!(Ecto.Changeset.change(ticket, status: "resolved"))
      path = "/support/tickets/#{ticket.reference}/rate"
      assert api(:post, path, nil, %{"rating" => 5}).status == 401
      assert api(:post, path, @customer_two, %{"rating" => 5}).status == 403
      assert api(:post, path, @agent, %{"rating" => 5}).status == 403
      assert repo().aggregate(SatisfactionRating, :count) == 0
      assert api(:post, path, %{id: "101"}, %{"rating" => 4, "rated_by_id" => 202}).status == 201
      assert %{rated_by_id: 101, rated_by_type: type, rating: 4} = repo().one!(SatisfactionRating)
      assert type == to_string(HostUser)
      assert api(:post, path, @customer_one, %{"rating" => 5}).status == 422
    end

    test "retains the valid guest token route and refuses invalid token shapes" do
      ticket = ticket_for!(@customer_one, "Guest resolved")

      repo().update!(
        Ecto.Changeset.change(ticket,
          status: "resolved",
          requester_id: nil,
          guest_token: "guest-private"
        )
      )

      assert api(:post, "/support/guest/tickets/wrong/rate", nil, %{"rating" => 5}).status == 404

      assert api(:post, "/support/guest/tickets/guest-private/rate", nil, %{"rating" => 5}).status ==
               201

      for token <- [nil, "", false, %{}] do
        response =
          Escalated.Controllers.SatisfactionRatingController.store_guest(conn(:post, "/"), %{
            "token" => token,
            "rating" => 5
          })

        assert response.status == 404
      end

      assert repo().aggregate(SatisfactionRating, :count) == 1
    end
  end
end
