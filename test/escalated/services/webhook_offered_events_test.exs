defmodule Escalated.Services.WebhookOfferedEventsTest do
  @moduledoc """
  Every event the webhook admin screen offers has to be dispatched by the
  operation that causes it.

  The screen lists seventeen events an admin can subscribe a webhook to. Nine
  had no dispatch anywhere: assignment fired only a plugin hook, tag and
  department changes fired nothing, an SLA breach was only recorded, and
  nothing emitted `ticket.updated`, `ticket.escalated` or `sla.warning`. A
  webhook subscribed to one of those saved fine and was never called.

  The offered list is read from the admin page through the router, so an event
  added to the screen later without an operation here fails this test.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{Department, EscalationRule, Tag, Webhook, WebhookDelivery}
  alias Escalated.Services.{AssignmentService, EscalationService, SlaService, TicketService}
  alias Escalated.Test.Router
  alias Escalated.Webhooks

  defp repo, do: Escalated.repo()

  setup do
    test_pid = self()
    Application.put_env(:escalated, :webhook_sync, true)

    Application.put_env(:escalated, :webhook_http_client, fn _url, _headers, body ->
      send(test_pid, {:webhook_request, Jason.decode!(body)})
      {:ok, %{status: 200, body: "ok"}}
    end)

    on_exit(fn ->
      Application.delete_env(:escalated, :webhook_sync)
      Application.delete_env(:escalated, :webhook_http_client)
    end)

    :ok
  end

  test "a webhook subscribed to any offered event is called when that event happens" do
    offered = offered_events()

    assert Enum.sort(offered) == Enum.sort(Map.keys(operations())),
           "the admin screen offers events this test has no operation for"

    failures =
      for {event, operation} <- Enum.sort(operations()),
          result = dispatch_result(event, operation),
          result != :ok do
        "#{event}: #{result}"
      end

    assert failures == [],
           "offered webhook events that are never delivered:\n  " <>
             Enum.join(failures, "\n  ")
  end

  test "tag and assignment events carry the tag and the agent" do
    subscribe_only(["ticket.tag_added", "ticket.assigned"])
    tag = tag!()

    {:ok, _} = TicketService.add_tags(ticket!(), [tag.id])
    {:ok, _} = AssignmentService.assign(ticket!(), 900)

    assert_received {:webhook_request, %{"event" => "ticket.tag_added", "payload" => tagged}}
    assert tagged["tag"] == %{"id" => tag.id, "name" => tag.name}

    assert_received {:webhook_request, %{"event" => "ticket.assigned", "payload" => assigned}}
    assert assigned["agent_id"] == 900
  end

  # The operation that causes each offered event. Anything an operation does
  # to set itself up (creating the ticket, assigning it first) may dispatch
  # other events; only the event under test has a subscribed webhook.
  defp operations do
    %{
      "ticket.created" => fn -> ticket!() end,
      "ticket.updated" => fn -> TicketService.change_priority(ticket!(), "high") end,
      "ticket.status_changed" => fn ->
        TicketService.transition_status(ticket!(), "in_progress")
      end,
      "ticket.resolved" => fn -> TicketService.transition_status(ticket!(), "resolved") end,
      "ticket.closed" => fn -> TicketService.transition_status(ticket!(), "closed") end,
      "ticket.reopened" => fn -> TicketService.transition_status(ticket!(), "reopened") end,
      "ticket.assigned" => fn -> AssignmentService.assign(ticket!(), 900) end,
      "ticket.unassigned" => &unassign/0,
      "ticket.escalated" => &escalate_by_rule/0,
      "ticket.priority_changed" => fn -> TicketService.change_priority(ticket!(), "urgent") end,
      "ticket.department_changed" => &change_department/0,
      "reply.created" => fn ->
        TicketService.reply(ticket!(), %{body: "Hi", is_internal: false})
      end,
      "note.created" => fn ->
        TicketService.reply(ticket!(), %{body: "Psst", is_internal: true})
      end,
      "sla.breached" => &breach_sla/0,
      "sla.warning" => &warn_sla/0,
      "ticket.tag_added" => fn -> TicketService.add_tags(ticket!(), [tag!().id]) end,
      "ticket.tag_removed" => &remove_tag/0
    }
  end

  defp unassign do
    {:ok, assigned} = AssignmentService.assign(ticket!(), 900)
    AssignmentService.unassign(assigned)
  end

  defp escalate_by_rule do
    ticket!(%{priority: "critical"})

    %EscalationRule{}
    |> EscalationRule.changeset(%{
      name: "Escalate critical #{System.unique_integer([:positive])}",
      trigger_type: "cron",
      conditions: [%{"field" => "priority", "value" => "critical"}],
      actions: [%{"type" => "escalate"}]
    })
    |> repo().insert!()

    EscalationService.evaluate_rules(repo())
  end

  defp change_department do
    department =
      %Department{}
      |> Department.changeset(%{name: "Billing #{System.unique_integer([:positive])}"})
      |> repo().insert!()

    TicketService.change_department(ticket!(), department)
  end

  defp breach_sla do
    ticket!(%{sla_first_response_due_at: minutes_from_now(-60)})
    SlaService.check_breaches()
  end

  defp warn_sla do
    ticket!(%{sla_first_response_due_at: minutes_from_now(10)})
    SlaService.check_warnings(30)
  end

  defp remove_tag do
    tag = tag!()
    {:ok, tagged} = TicketService.add_tags(ticket!(), [tag.id])
    TicketService.remove_tags(tagged, [tag.id])
  end

  # :ok when a webhook subscribed to only `event` recorded a delivery for it.
  defp dispatch_result(event, operation) do
    subscribe_only([event])

    try do
      operation.()

      if repo().exists?(from(d in WebhookDelivery, where: d.event == ^event)),
        do: :ok,
        else: "no delivery"
    rescue
      error -> "raised #{Exception.message(error)}"
    end
  end

  defp subscribe_only(events) do
    repo().delete_all(WebhookDelivery)
    repo().delete_all(Webhook)

    {:ok, _} =
      Webhooks.create(repo(), %{url: "https://example.test/hook", events: events, active: true})
  end

  defp ticket!(attrs \\ %{}) do
    {:ok, ticket} =
      TicketService.create(Map.merge(%{subject: "Printer", description: "Jammed"}, attrs))

    ticket
  end

  defp tag! do
    %Tag{}
    |> Tag.changeset(%{name: "vip-#{System.unique_integer([:positive])}"})
    |> repo().insert!()
  end

  defp minutes_from_now(minutes) do
    DateTime.utc_now() |> DateTime.add(minutes * 60, :second) |> DateTime.truncate(:second)
  end

  defp offered_events do
    conn =
      conn(:get, "/support/admin/webhooks")
      |> init_test_session(%{})
      |> assign(:current_user, %{id: 1})
      |> put_req_header("x-inertia", "true")
      |> put_req_header("x-inertia-version", inertia_version())
      |> Router.call(Router.init([]))

    assert conn.status == 200
    Jason.decode!(conn.resp_body)["props"]["available_events"]
  end

  defp inertia_version do
    conn(:get, "/")
    |> init_test_session(%{})
    |> Inertia.Plug.call(Inertia.Plug.init([]))
    |> Map.fetch!(:private)
    |> Map.fetch!(:inertia_version)
    |> to_string()
  end
end
