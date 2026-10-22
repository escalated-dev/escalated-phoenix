defmodule Escalated.Services.CustomStatusLifecycleTest do
  @moduledoc """
  Custom ticket statuses are sub-statuses of a category. Giving a ticket one
  moves its built-in status to the category's anchor through the normal
  status change, so every lifecycle rule keyed off the built-in status (the
  resolved/closed stamps, SLA, activity, events, workflows) follows; setting a
  built-in status clears the custom one.

  There is no auto-close job in this package (`auto_close_resolved_after_days`
  is a config key nothing reads), so there is no auto-close case here.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{Macro, Ticket, TicketActivity, TicketStatus}
  alias Escalated.Services.{MacroService, SlaService, TicketService, WorkflowExecutor}
  alias Escalated.Webhooks

  @events ~w(ticket.status_changed ticket.resolved ticket.updated)

  defp repo, do: Escalated.repo()

  setup do
    Application.put_env(:escalated, :agent_check, &Map.get(&1, :is_agent, false))
    Application.put_env(:escalated, :webhook_sync, true)
    test_pid = self()

    Application.put_env(:escalated, :webhook_http_client, fn _url, _headers, body ->
      send(test_pid, {:webhook, Jason.decode!(body)["event"]})
      {:ok, %{status: 200, body: "ok"}}
    end)

    on_exit(fn ->
      Enum.each(
        [:agent_check, :webhook_sync, :webhook_http_client],
        &Application.delete_env(:escalated, &1)
      )
    end)

    {:ok, _} =
      Webhooks.create(repo(), %{url: "https://hooks.test/in", events: @events, active: true})

    customer = host_user!(%{name: "Cy Customer", email: "cy@example.test"})

    {:ok, ticket} =
      TicketService.create(%{
        subject: "Printer",
        description: "Jammed",
        requester_id: customer.id,
        requester_type: "user"
      })

    flush_events()

    %{
      agent: host_user!(%{name: "Al Agent", is_agent: true}),
      admin: host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true}),
      customer: customer,
      ticket: ticket,
      fixed: status!("Fixed", "fixed", "solved", "#22c55e"),
      verified: status!("Verified", "verified", "solved", "#16a34a"),
      vendor: status!("Waiting on vendor", "waiting_on_vendor", "pending", "#eab308"),
      parts: status!("Awaiting parts", "awaiting_parts", "on_hold", "#a855f7"),
      triage: status!("Triage", "triage", "new", "#0ea5e9")
    }
  end

  defp status!(label, slug, category, color) do
    %TicketStatus{}
    |> TicketStatus.changeset(%{label: label, slug: slug, category: category, color: color})
    |> repo().insert!()
  end

  defp events do
    receive do
      {:webhook, event} -> [event | events()]
    after
      0 -> []
    end
  end

  defp flush_events, do: events()

  defp reload(ticket), do: repo().get!(Ticket, ticket.id)

  defp agent_status(agent, ticket, status) do
    visit(:post, "/support/agent/tickets/#{ticket.reference}/status", agent, %{
      "status" => status
    })
  end

  defp api(method, user, path, body) do
    base =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    base
    |> put_req_header("accept", "application/json")
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> Escalated.Test.Router.call(Escalated.Test.Router.init([]))
  end

  describe "setting a custom status through the status endpoints" do
    test "a solved status resolves the ticket and records the custom status", ctx do
      conn = agent_status(ctx.agent, ctx.ticket, "fixed")
      assert conn.status in [302, 303]

      ticket = reload(ctx.ticket)
      assert ticket.status == "resolved"
      assert ticket.ticket_status_id == ctx.fixed.id
      assert ticket.resolved_at

      received = events()
      assert "ticket.status_changed" in received
      assert "ticket.resolved" in received

      activity =
        repo().one!(
          from(a in TicketActivity,
            where: a.ticket_id == ^ticket.id and a.action == "status_changed"
          )
        )

      assert activity.details["to"] == "resolved"
      assert activity.details["custom_status"] == "fixed"
    end

    test "a pending status maps to waiting_on_customer", ctx do
      assert agent_status(ctx.agent, ctx.ticket, "waiting_on_vendor").status in [302, 303]

      ticket = reload(ctx.ticket)
      assert ticket.status == "waiting_on_customer"
      assert ticket.ticket_status_id == ctx.vendor.id
    end

    test "on_hold anchors to in_progress and new to open", ctx do
      {:ok, ticket} = TicketService.transition_status(ctx.ticket, "awaiting_parts")
      assert {ticket.status, ticket.ticket_status_id} == {"in_progress", ctx.parts.id}

      {:ok, ticket} = TicketService.transition_status(ticket, "triage")
      assert {ticket.status, ticket.ticket_status_id} == {"open", ctx.triage.id}
    end

    test "the admin and API status endpoints take a custom slug too", ctx do
      conn =
        visit(:post, "/support/admin/tickets/#{ctx.ticket.reference}/status", ctx.admin, %{
          "status" => "awaiting_parts"
        })

      assert conn.status in [302, 303]
      assert reload(ctx.ticket).ticket_status_id == ctx.parts.id

      conn =
        api(:patch, ctx.agent, "/support/api/v1/tickets/#{ctx.ticket.reference}/status", %{
          "status" => "fixed"
        })

      assert conn.status == 200
      data = Jason.decode!(conn.resp_body)["data"]
      assert data["status"] == "resolved"
      assert data["status_category"] == "solved"

      assert data["custom_status"] == %{
               "id" => ctx.fixed.id,
               "label" => "Fixed",
               "slug" => "fixed",
               "color" => "#22c55e",
               "category" => "solved"
             }
    end

    test "an unknown status is still rejected", ctx do
      conn = agent_status(ctx.agent, ctx.ticket, "nonsense")

      assert conn.status == 422
      assert reload(ctx.ticket).status == "open"
    end

    test "the bulk action takes a custom slug", ctx do
      conn =
        visit(:post, "/support/agent/tickets/bulk", ctx.agent, %{
          "ticket_ids" => [ctx.ticket.id],
          "action" => "status",
          "value" => "waiting_on_vendor"
        })

      assert conn.status in [302, 303]
      ticket = reload(ctx.ticket)
      assert {ticket.status, ticket.ticket_status_id} == {"waiting_on_customer", ctx.vendor.id}
    end

    test "macro set_status and workflow change_status take a custom slug", ctx do
      macro =
        repo().insert!(
          Macro.changeset(%Macro{}, %{
            name: "Park",
            actions: [%{"type" => "set_status", "value" => "awaiting_parts"}]
          })
        )

      _ = MacroService.apply(repo(), macro, ctx.ticket, ctx.agent.id)
      ticket = reload(ctx.ticket)
      assert {ticket.status, ticket.ticket_status_id} == {"in_progress", ctx.parts.id}

      assert {:ok, "change_status"} =
               WorkflowExecutor.dispatch_action(ticket, %{
                 "type" => "change_status",
                 "value" => "fixed"
               })

      ticket = reload(ctx.ticket)
      assert {ticket.status, ticket.ticket_status_id} == {"resolved", ctx.fixed.id}
    end
  end

  describe "lifecycle keyed off the category" do
    test "a ticket in a solved custom status is skipped by the SLA breach check", ctx do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, ticket} =
        ctx.ticket
        |> Ticket.changeset(%{sla_resolution_due_at: past, first_response_at: past})
        |> repo().update()

      {:ok, _} = TicketService.transition_status(ticket, "fixed")

      refute ctx.ticket.id in Enum.map(SlaService.check_breaches(), & &1.id)
      refute reload(ctx.ticket).sla_breached
    end

    test "setting a built-in status clears the custom status", ctx do
      {:ok, ticket} = TicketService.transition_status(ctx.ticket, "fixed")
      assert ticket.ticket_status_id == ctx.fixed.id

      {:ok, ticket} = TicketService.transition_status(ticket, "resolved")
      assert ticket.status == "resolved"
      assert reload(ticket).ticket_status_id == nil

      {:ok, ticket} = TicketService.transition_status(ticket, "awaiting_parts")
      until = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      {:ok, ticket} = TicketService.snooze_ticket(ticket, until)
      assert reload(ticket).ticket_status_id == nil
    end

    test "a move within one category is saved and announced once", ctx do
      {:ok, ticket} = TicketService.transition_status(ctx.ticket, "fixed")
      resolved_at = ticket.resolved_at
      flush_events()

      {:ok, ticket} = TicketService.transition_status(ticket, "verified")

      assert ticket.status == "resolved"
      assert reload(ticket).ticket_status_id == ctx.verified.id
      assert reload(ticket).resolved_at == resolved_at

      received = events()
      assert Enum.count(received, &(&1 == "ticket.status_changed")) == 1
      refute "ticket.resolved" in received
    end

    test "a workflow or macro setting the status it already has is a no-op", ctx do
      macro =
        repo().insert!(
          Macro.changeset(%Macro{}, %{
            name: "Fix",
            actions: [%{"type" => "set_status", "value" => "fixed"}]
          })
        )

      _ = MacroService.apply(repo(), macro, ctx.ticket, ctx.agent.id)
      flush_events()
      _ = MacroService.apply(repo(), macro, reload(ctx.ticket), ctx.agent.id)

      refute "ticket.status_changed" in events()
    end

    test "changing a status's category does not move tickets already in it", ctx do
      {:ok, ticket} = TicketService.transition_status(ctx.ticket, "waiting_on_vendor")

      ctx.vendor |> TicketStatus.changeset(%{category: "solved"}) |> repo().update!()

      reloaded = reload(ticket)
      assert reloaded.status == "waiting_on_customer"
      assert reloaded.ticket_status_id == ctx.vendor.id

      {:ok, other} = TicketService.create(%{subject: "Other", description: "x"})
      {:ok, other} = TicketService.transition_status(other, "waiting_on_vendor")
      assert other.status == "resolved"
    end

    test "list filters by a custom slug", ctx do
      {:ok, _} = TicketService.transition_status(ctx.ticket, "fixed")
      {:ok, other} = TicketService.create(%{subject: "Other", description: "x"})
      {:ok, _} = TicketService.transition_status(other, "resolved")

      assert Enum.map(TicketService.list(%{status: "fixed"}), & &1.id) == [ctx.ticket.id]

      assert Enum.sort(Enum.map(TicketService.list(%{status: "resolved"}), & &1.id)) ==
               Enum.sort([ctx.ticket.id, other.id])
    end
  end

  describe "what each audience sees" do
    test "the agent ticket page carries custom_status and status_category", ctx do
      {:ok, _} = TicketService.transition_status(ctx.ticket, "awaiting_parts")

      props =
        visit(:get, "/support/agent/tickets/#{ctx.ticket.reference}", ctx.agent)
        |> page!("Escalated/Agent/TicketShow")

      assert props["ticket"]["status"] == "in_progress"
      assert props["ticket"]["status_category"] == "on_hold"

      assert props["ticket"]["custom_status"] == %{
               "id" => ctx.parts.id,
               "label" => "Awaiting parts",
               "slug" => "awaiting_parts",
               "color" => "#a855f7",
               "category" => "on_hold"
             }
    end

    test "a ticket without a custom status gets its built-in category", ctx do
      {:ok, _} = TicketService.transition_status(ctx.ticket, "waiting_on_customer")

      props =
        visit(:get, "/support/agent/tickets", ctx.agent)
        |> page!("Escalated/Agent/TicketIndex")

      [row] = props["tickets"]["data"]
      assert row["custom_status"] == nil
      assert row["status_category"] == "pending"
    end

    test "the customer view shows the built-in status only", ctx do
      {:ok, _} = TicketService.transition_status(ctx.ticket, "awaiting_parts")

      conn = visit(:get, "/support/tickets/#{ctx.ticket.reference}", ctx.customer)
      props = page!(conn, "Escalated/Customer/Show")

      assert props["ticket"]["status"] == "in_progress"
      refute Map.has_key?(props["ticket"], "custom_status")
      refute conn.resp_body =~ "Awaiting parts"
      refute conn.resp_body =~ "awaiting_parts"

      index = visit(:get, "/support/tickets", ctx.customer)
      page!(index, "Escalated/Customer/Index")
      refute index.resp_body =~ "Awaiting parts"
    end
  end
end
