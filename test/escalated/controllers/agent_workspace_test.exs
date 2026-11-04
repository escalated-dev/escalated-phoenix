defmodule Escalated.Controllers.AgentWorkspaceTest do
  @moduledoc """
  What the agent ticket page needs beyond the ticket itself: the agents it can
  be reassigned to, the requester's other tickets, and snoozing from the agent
  panel (after escalated-laravel's `AgentWorkspaceTest`).
  """
  use Escalated.PageCase

  alias Escalated.Controllers.Agent.TicketController
  alias Escalated.RoutePermissions
  alias Escalated.Schemas.{Department, DepartmentAgent, Ticket}

  defp repo, do: Escalated.repo()

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp minutes(n), do: DateTime.add(now(), n * 60, :second)

  defp ticket!(attrs \\ %{}) do
    base = %Ticket{
      subject: "Ticket",
      description: "Body",
      status: "open",
      priority: "low",
      reference: "ESC-#{System.unique_integer([:positive])}"
    }

    repo().insert!(struct(base, attrs))
  end

  defp show(user, ticket) do
    visit(:get, "/support/agent/tickets/#{ticket.reference}", user)
    |> page!("Escalated/Agent/TicketShow")
  end

  defp snooze(user, ticket, body),
    do: visit(:post, "/support/agent/tickets/#{ticket.reference}/snooze", user, body)

  defp department!(name), do: repo().insert!(Department.changeset(%Department{}, %{name: name}))

  defp department_visibility do
    Application.put_env(:escalated, :visibility, :department)
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))

    on_exit(fn ->
      Application.delete_env(:escalated, :visibility)
      Application.delete_env(:escalated, :agent_check)
    end)
  end

  setup do
    agent = host_user!(%{name: "Ada Agent", is_agent: true})
    %{agent: agent}
  end

  # --- Reassigning -----------------------------------------------------------

  test "sends the agents and admins a ticket can be assigned to, by id and name", ctx do
    admin = host_user!(%{name: "Al Admin", is_admin: true})
    host_user!(%{name: "Cass Customer"})

    assert show(ctx.agent, ticket!())["agents"] == [
             %{"id" => ctx.agent.id, "name" => "Ada Agent"},
             %{"id" => admin.id, "name" => "Al Admin"}
           ]
  end

  test "leaves out agents who cannot see the ticket under department visibility", ctx do
    other = host_user!(%{name: "Otto Other", is_agent: true})
    support = department!("Support")
    repo().insert!(%DepartmentAgent{department_id: support.id, agent_id: ctx.agent.id})
    ticket = ticket!(%{department_id: support.id})
    department_visibility()

    names = show(ctx.agent, ticket)["agents"] |> Enum.map(& &1["name"])

    assert "Ada Agent" in names
    refute other.name in names
  end

  # --- The requester's other tickets -------------------------------------------

  test "sends the requester's other tickets, newest first, at most five", ctx do
    customer = host_user!(%{name: "Cass Customer"})
    requester = %{requester_id: customer.id, requester_type: "user"}

    older =
      for i <- 1..6 do
        ticket!(
          Map.merge(requester, %{subject: "Earlier #{i}", inserted_at: minutes(-(10 - i) * 1440)})
        )
      end

    ticket!(%{subject: "Someone else", requester_id: customer.id + 1000, requester_type: "user"})
    ticket = ticket!(Map.merge(requester, %{inserted_at: now()}))

    recent = show(ctx.agent, ticket)["ticket"]["requester_tickets"]

    assert Enum.map(recent, & &1["subject"]) ==
             ["Earlier 6", "Earlier 5", "Earlier 4", "Earlier 3", "Earlier 2"]

    assert Map.keys(hd(recent)) |> Enum.sort() ==
             Enum.sort(~w(id reference subject status created_at updated_at))

    assert hd(recent)["reference"] == List.last(older).reference
    assert hd(recent)["status"] == "open"
    assert {:ok, _, _} = DateTime.from_iso8601(hd(recent)["created_at"])
  end

  test "matches a guest requester's other tickets by email", ctx do
    ticket!(%{
      guest_email: "guest@example.com",
      guest_name: "Gus",
      subject: "Earlier guest ticket"
    })

    ticket!(%{guest_email: "other@example.com", subject: "Another guest"})
    ticket = ticket!(%{guest_email: "guest@example.com", guest_name: "Gus"})

    recent = show(ctx.agent, ticket)["ticket"]["requester_tickets"]

    assert Enum.map(recent, & &1["subject"]) == ["Earlier guest ticket"]
  end

  test "only lists requester tickets the agent may see", ctx do
    customer = host_user!(%{name: "Cass Customer"})
    requester = %{requester_id: customer.id, requester_type: "user"}
    support = department!("Support")
    billing = department!("Billing")
    repo().insert!(%DepartmentAgent{department_id: support.id, agent_id: ctx.agent.id})
    ticket!(Map.merge(requester, %{department_id: support.id, subject: "Visible"}))
    ticket!(Map.merge(requester, %{department_id: billing.id, subject: "Hidden"}))
    ticket = ticket!(Map.merge(requester, %{department_id: support.id}))
    department_visibility()

    recent = show(ctx.agent, ticket)["ticket"]["requester_tickets"]

    assert Enum.map(recent, & &1["subject"]) == ["Visible"]
  end

  test "sends an empty list for a ticket with no known requester", ctx do
    ticket!()
    ticket = ticket!()

    assert show(ctx.agent, ticket)["ticket"]["requester_tickets"] == []
  end

  # --- Snoozing from the agent panel ---------------------------------------------

  test "lets an agent snooze a ticket", ctx do
    ticket = ticket!()
    until = minutes(24 * 60)

    conn = snooze(ctx.agent, ticket, %{"snoozed_until" => DateTime.to_iso8601(until)})

    assert conn.status == 302
    assert location(conn) == "/support/agent/tickets/#{ticket.reference}"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Ticket snoozed."

    ticket = repo().get!(Ticket, ticket.id)
    assert DateTime.compare(ticket.snoozed_until, until) == :eq
    assert ticket.snoozed_by == ctx.agent.id
  end

  test "rejects a snooze time in the past, or none at all", ctx do
    ticket = ticket!()

    for body <- [
          %{"snoozed_until" => DateTime.to_iso8601(minutes(-60))},
          %{"snoozed_until" => "not a date"},
          %{}
        ] do
      conn = snooze(ctx.agent, ticket, body)
      assert conn.status == 302, inspect(body)
      assert Map.has_key?(get_session(conn, "inertia_errors") || %{}, "snoozed_until")

      json =
        conn(:post, "/support/agent/tickets/#{ticket.reference}/snooze", Jason.encode!(body))
        |> put_req_header("content-type", "application/json")
        |> init_test_session(%{})
        |> assign(:current_user, ctx.agent)
        |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))

      assert json.status == 422, inspect(body)
      assert %{"errors" => %{"snoozed_until" => [_ | _]}} = Jason.decode!(json.resp_body)
    end

    assert is_nil(repo().get!(Ticket, ticket.id).snoozed_until)
  end

  test "lets an agent unsnooze a ticket", ctx do
    ticket = ticket!(%{status: "in_progress"})
    snooze(ctx.agent, ticket, %{"snoozed_until" => DateTime.to_iso8601(minutes(24 * 60))})

    conn = visit(:post, "/support/agent/tickets/#{ticket.reference}/unsnooze", ctx.agent)

    assert conn.status == 302
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Ticket unsnoozed."

    ticket = repo().get!(Ticket, ticket.id)
    assert is_nil(ticket.snoozed_until)
    assert ticket.status == "in_progress"
  end

  test "does not let a customer snooze through the agent panel" do
    customer = host_user!(%{name: "Cass Customer"})
    ticket = ticket!()

    conn = snooze(customer, ticket, %{"snoozed_until" => DateTime.to_iso8601(minutes(60))})

    assert conn.status == 403
    assert is_nil(repo().get!(Ticket, ticket.id).snoozed_until)
  end

  test "does not let an agent snooze a ticket outside their departments", ctx do
    ticket = ticket!(%{department_id: department!("Billing").id})
    department_visibility()

    conn = snooze(ctx.agent, ticket, %{"snoozed_until" => DateTime.to_iso8601(minutes(60))})

    assert conn.status == 404
    assert is_nil(repo().get!(Ticket, ticket.id).snoozed_until)
  end

  test "maps the agent snooze routes to the ticket edit permission" do
    assert RoutePermissions.required(TicketController, :snooze) == ["ticket.edit"]
    assert RoutePermissions.required(TicketController, :unsnooze) == ["ticket.edit"]
  end
end
