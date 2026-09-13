defmodule Escalated.RouterWiringTest do
  @moduledoc """
  Every route the package mounts has to reach a controller action that exists.

  A route naming a missing controller module or action compiles with nothing
  worse than a warning and answers 500 on the first request. Two kinds shipped:
  the live chat routes named fully qualified modules inside scopes that already
  alias `Escalated.Controllers.*`, so the router looked for
  `Escalated.Controllers.Agent.Escalated.Controllers.Agent.ChatController`; and
  the admin snooze, unsnooze and split routes pointed at an admin controller
  with no such actions. Walking `__routes__/0` checks every route at once,
  including the ones added after this test.
  """
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.TicketService
  alias Escalated.Test.Router

  defp repo, do: Escalated.repo()

  setup do
    on_exit(fn -> Application.delete_env(:escalated, :admin_check) end)
    :ok
  end

  describe "route table" do
    test "every route's controller is loaded and exports its action" do
      routes = Router.__routes__()

      broken =
        for route <- routes, not reachable?(route) do
          verb = route.verb |> to_string() |> String.upcase()
          "#{verb} #{route.path} -> #{inspect(route.plug)}.#{route.plug_opts}/2"
        end

      assert broken == [],
             "routes pointing at a missing controller or action:\n  " <>
               Enum.join(broken, "\n  ")
    end

    test "the walk covers the chat and admin ticket routes" do
      paths = Enum.map(Router.__routes__(), & &1.path)

      for path <- [
            "/support/agent/chat/sessions",
            "/support/widget/chat/availability",
            "/support/admin/tickets/:reference/snooze",
            "/support/admin/tickets/:reference/unsnooze",
            "/support/admin/tickets/:reference/split"
          ] do
        assert path in paths
      end
    end
  end

  describe "live chat routes" do
    test "the agent session list answers" do
      conn = request(:get, "/support/agent/chat/sessions")

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"data" => []}
    end

    test "the widget availability check answers" do
      conn = request(:get, "/support/widget/chat/availability")

      assert conn.status == 200
      assert %{"data" => _status} = Jason.decode!(conn.resp_body)
    end
  end

  describe "admin snooze, unsnooze and split" do
    test "snooze and unsnooze change the ticket" do
      ticket = ticket!()

      snoozed =
        request(:post, "/support/admin/tickets/#{ticket.reference}/snooze", %{
          "snoozed_until" => "2030-01-01T09:00:00Z"
        })

      assert snoozed.status == 200
      assert repo().get!(Ticket, ticket.id).status == "snoozed"

      woken = request(:post, "/support/admin/tickets/#{ticket.reference}/unsnooze")

      assert woken.status == 200
      assert repo().get!(Ticket, ticket.id).status == "open"
    end

    test "split creates a ticket from the reply" do
      ticket = ticket!()
      {:ok, reply} = TicketService.reply(ticket, %{body: "Second problem", is_internal: false})

      conn =
        request(:post, "/support/admin/tickets/#{ticket.reference}/split", %{
          "reply_id" => reply.id
        })

      assert conn.status == 201
      assert repo().aggregate(Ticket, :count) == 2
    end

    test "they stay behind the admin check" do
      Application.put_env(:escalated, :admin_check, &Map.get(&1, :is_admin, false))
      ticket = ticket!()

      conn =
        request(:post, "/support/admin/tickets/#{ticket.reference}/snooze", %{
          "snoozed_until" => "2030-01-01T09:00:00Z"
        })

      assert conn.status == 403
      assert repo().get!(Ticket, ticket.id).status == "open"
    end
  end

  defp reachable?(route) do
    Code.ensure_loaded?(route.plug) and function_exported?(route.plug, route.plug_opts, 2)
  end

  defp ticket! do
    {:ok, ticket} = TicketService.create(%{subject: "Printer", description: "Jammed"})
    ticket
  end

  # A signed-in user with no agent or admin flag. With no :agent_check or
  # :admin_check configured the scopes let any signed-in user through, which
  # keeps these requests about the route rather than the permission.
  #
  # A missing controller raises out of the router instead of returning a
  # response; the rescue turns that into a failure that names the error.
  defp request(method, path, body \\ nil) do
    conn =
      case body do
        nil ->
          conn(method, path)

        body ->
          method
          |> conn(path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    conn
    |> init_test_session(%{})
    |> assign(:current_user, %{id: 1})
    |> put_req_header("accept", "application/json")
    |> Router.call(Router.init([]))
  rescue
    error -> flunk("#{method} #{path} raised instead of answering: #{Exception.message(error)}")
  end
end
