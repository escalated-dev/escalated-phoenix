defmodule Escalated.Controllers.TicketVisibilityTest do
  use Escalated.DataCase, async: false

  import Plug.Conn
  import Plug.Test
  alias Ecto.Adapters.SQL.Sandbox
  alias Escalated.HostTestRepo
  alias Escalated.Services.TicketService
  alias Escalated.Test.{HostUser, Router}

  setup do
    :ok = Sandbox.checkout(HostTestRepo)
    Sandbox.mode(HostTestRepo, {:shared, self()})
    Application.put_env(:escalated, :user_repo, HostTestRepo)
    Application.put_env(:escalated, :user_schema, HostUser)
    Application.put_env(:escalated, :visibility, :department)
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))

    on_exit(fn ->
      for key <- [:user_repo, :user_schema, :visibility, :agent_check] do
        Application.delete_env(:escalated, key)
      end

      Sandbox.checkin(HostTestRepo)
    end)

    {:ok, ticket} =
      TicketService.create(%{subject: "Hidden account ticket", description: "Private"})

    %{ticket: ticket}
  end

  for {name, method, suffix, body} <- [
        {"detail", :get, "", nil},
        {"reply", :post, "/reply", %{body: "Unauthorized reply"}},
        {"update", :patch, "/priority", %{priority: "urgent"}},
        {"close", :patch, "/status", %{status: "closed"}},
        {"assign", :post, "/assign", %{agent_id: 900}}
      ] do
    @tag :visibility_control
    test "department restriction covers API #{name}", %{ticket: ticket} do
      response =
        request(
          unquote(method),
          "/support/api/v1/tickets/#{ticket.reference}" <> unquote(suffix),
          unquote(Macro.escape(body))
        )

      assert response.status == 404
      refute response.resp_body =~ ticket.subject
    end
  end

  for {name, query} <- [{"list", ""}, {"search", "?search=Hidden"}] do
    @tag :visibility_control
    test "department restriction covers API #{name}", %{ticket: ticket} do
      response = request(:get, "/support/api/v1/tickets" <> unquote(query), nil)
      assert response.status == 200
      assert Jason.decode!(response.resp_body)["data"] == []
      refute response.resp_body =~ ticket.reference
    end
  end

  defp request(method, path, body) do
    method
    |> conn(path, if(body, do: Jason.encode!(body), else: nil))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> init_test_session(%{})
    |> assign(:current_user, %{id: 900, is_agent: true})
    |> Router.call(Router.init([]))
  end
end
