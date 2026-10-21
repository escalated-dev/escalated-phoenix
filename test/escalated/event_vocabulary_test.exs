defmodule Escalated.EventVocabularyTest do
  @moduledoc """
  The event vocabulary of escalated-developer-context
  decisions/2026-10-21-event-vocabulary.md, checked through the real router and
  services.

    * The workflow builder offers every event this package fires, under its
      canonical name, and each of them runs a workflow saved against it
      (`ticket.updated` and `ticket.assigned` used to be missing).
    * Legacy names stored on a workflow or a webhook keep working on read, and
      are stored and shown under their canonical name.
    * The builder can create a `delay` action, and a saved delay defers the
      actions after it.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query
  import Plug.Conn
  import Plug.Test

  alias Escalated.Schemas.{
    DelayedAction,
    Department,
    EscalationRule,
    Tag,
    Ticket,
    Webhook,
    WebhookDelivery,
    Workflow,
    WorkflowLog
  }

  alias Escalated.Services.{
    AssignmentService,
    ChatSessionService,
    EscalationService,
    SlaService,
    TicketService,
    WorkflowExecutor
  }

  alias Escalated.Test.Router
  alias Escalated.Webhooks

  @workflows "/support/admin/workflows"
  @webhooks "/support/admin/webhooks"

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

  describe "workflow triggers" do
    test "the builder offers every fired event, and each one runs its workflow" do
      offered = form_props()["trigger_events"] |> option_values()

      assert Enum.sort(offered) == Enum.sort(Map.keys(operations())),
             "the builder offers triggers this test has no operation for"

      assert "ticket.updated" in offered
      assert "ticket.assigned" in offered

      failures =
        for {event, operation} <- Enum.sort(operations()),
            result = workflow_result(event, operation),
            result != :ok do
          "#{event}: #{result}"
        end

      assert failures == [],
             "offered workflow triggers that never run:\n  " <> Enum.join(failures, "\n  ")
    end

    test "the builder offers only canonical names" do
      offered = form_props()["trigger_events"] |> option_values()

      for event <- offered do
        assert Escalated.Events.canonical(event) == event
      end

      refute "ticket.tagged" in offered
      refute "ticket.replied" in offered
    end

    test "a ticket.assigned workflow runs when a ticket is assigned" do
      wf = workflow!("ticket.assigned", [%{"type" => "change_priority", "value" => "urgent"}])
      ticket = ticket!()

      {:ok, _} = AssignmentService.assign(ticket, 900)

      assert repo().get!(Ticket, ticket.id).priority == "urgent"
      assert repo().get_by(WorkflowLog, workflow_id: wf.id, ticket_id: ticket.id)
    end

    test "a ticket.updated workflow runs when a ticket's fields change" do
      wf = workflow!("ticket.updated", [%{"type" => "add_tag", "value" => tag!().name}])
      ticket = ticket!()

      {:ok, _} = TicketService.change_priority(ticket, "high")

      assert repo().get_by(WorkflowLog, workflow_id: wf.id, ticket_id: ticket.id)
      assert [_] = repo().preload(repo().get!(Ticket, ticket.id), :tags).tags
    end
  end

  describe "legacy workflow triggers" do
    test "a workflow stored as ticket.replied runs on a public reply" do
      wf = workflow!("ticket.replied", [%{"type" => "change_priority", "value" => "high"}])
      ticket = ticket!()

      {:ok, _} = TicketService.reply(ticket, %{body: "Hi", is_internal: false})

      assert repo().get_by(WorkflowLog, workflow_id: wf.id, ticket_id: ticket.id)
    end

    test "workflows stored as ticket.tagged and internal_note.added still run" do
      tagged = workflow!("ticket.tagged", [%{"type" => "change_priority", "value" => "high"}])
      noted = workflow!("internal_note.added", [%{"type" => "change_priority", "value" => "low"}])
      ticket = ticket!()

      {:ok, _} = TicketService.add_tags(ticket, [tag!().id])
      {:ok, _} = TicketService.reply(ticket, %{body: "Psst", is_internal: true})

      assert repo().get_by(WorkflowLog, workflow_id: tagged.id, ticket_id: ticket.id)
      assert repo().get_by(WorkflowLog, workflow_id: noted.id, ticket_id: ticket.id)
    end

    test "a legacy trigger posted by the builder is stored, and shown, canonically" do
      body = %{
        "name" => "Old client",
        "trigger_event" => "ticket.replied",
        "conditions" => %{"all" => []},
        "actions" => [%{"type" => "change_priority", "value" => "high"}]
      }

      assert visit(:post, @workflows, body).status == 302
      [wf] = repo().all(Workflow)
      assert wf.trigger_event == "reply.created"

      legacy = workflow!("ticket.tagged", [%{"type" => "change_priority", "value" => "high"}])
      props = visit(:get, "#{@workflows}/#{legacy.id}/edit") |> page() |> Map.fetch!("props")
      assert props["workflow"]["trigger_event"] == "ticket.tag_added"

      listed = visit(:get, @workflows) |> page() |> get_in(["props", "workflows"])

      assert Enum.all?(
               listed,
               &(Escalated.Events.canonical(&1["trigger_event"]) == &1["trigger_event"])
             )
    end
  end

  describe "legacy webhook subscriptions" do
    test "a webhook subscribed to legacy names receives the canonical events" do
      {:ok, _} =
        Webhooks.create(repo(), %{
          url: "https://example.test/hook",
          events: ["ticket.replied", "internal_note.added", "ticket.tagged", "ticket.untagged"],
          active: true
        })

      tag = tag!()
      ticket = ticket!()
      {:ok, tagged} = TicketService.add_tags(ticket, [tag.id])
      {:ok, _} = TicketService.remove_tags(tagged, [tag.id])
      {:ok, _} = TicketService.reply(ticket, %{body: "Hi", is_internal: false})
      {:ok, _} = TicketService.reply(ticket, %{body: "Psst", is_internal: true})

      delivered = repo().all(from(d in WebhookDelivery, select: d.event))

      assert Enum.sort(delivered) ==
               Enum.sort(~w(ticket.tag_added ticket.tag_removed reply.created note.created))
    end

    test "the webhook admin stores and shows legacy names canonically" do
      body = %{
        "url" => "https://example.test/hook",
        "events" => ["ticket.replied", "reply.created", "chat.session_started"]
      }

      assert visit(:post, @webhooks, body).status == 302
      [webhook] = repo().all(Webhook)
      assert webhook.events == ["reply.created", "chat.started"]

      # A row saved before this change keeps its legacy names in the database.
      {1, _} =
        repo().update_all(from(w in Webhook, where: w.id == ^webhook.id),
          set: [events: ["ticket.tagged", "internal_note.added"]]
        )

      props = visit(:get, @webhooks) |> page() |> Map.fetch!("props")
      [listed] = props["webhooks"]
      assert listed["events"] == ["ticket.tag_added", "note.created"]

      for event <- props["available_events"] do
        assert Escalated.Events.canonical(event) == event
      end
    end
  end

  describe "delay" do
    test "the builder offers delay" do
      assert "delay" in option_values(form_props()["action_types"])
    end

    test "a delay saved through the builder defers the actions after it" do
      body = %{
        "name" => "Wait, then escalate",
        "trigger_event" => "ticket.created",
        "conditions" => %{"all" => []},
        "actions" => [
          %{"type" => "change_priority", "value" => "high"},
          %{"type" => "delay", "value" => 30},
          %{"type" => "change_status", "value" => "escalated"}
        ]
      }

      assert visit(:post, @workflows, body).status == 302
      [wf] = repo().all(Workflow)

      ticket = ticket!()
      reloaded = repo().get!(Ticket, ticket.id)
      assert reloaded.priority == "high"
      assert reloaded.status == "open"

      [delayed] = repo().all(DelayedAction)
      assert delayed.workflow_id == wf.id
      assert delayed.ticket_id == ticket.id
      assert delayed.action_data == %{"type" => "change_status", "value" => "escalated"}
      assert DateTime.diff(delayed.execute_at, DateTime.utc_now()) in 1700..1800

      log = repo().get_by!(WorkflowLog, workflow_id: wf.id, ticket_id: ticket.id)
      assert log.status == "success"

      repo().update_all(DelayedAction, set: [execute_at: ~U[2020-01-01 00:00:00Z]])
      assert {1, 0} = WorkflowExecutor.run_due_delayed_actions()
      assert repo().get!(Ticket, ticket.id).status == "escalated"
    end
  end

  # The operation that causes each event. Setting up (creating the ticket,
  # assigning it first) may fire other events; only the event under test has a
  # workflow saved against it.
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
      "ticket.unassigned" => fn ->
        {:ok, assigned} = AssignmentService.assign(ticket!(), 900)
        AssignmentService.unassign(assigned)
      end,
      "ticket.escalated" => &escalate_by_rule/0,
      "ticket.priority_changed" => fn -> TicketService.change_priority(ticket!(), "urgent") end,
      "ticket.department_changed" => fn ->
        TicketService.change_department(ticket!(), department!())
      end,
      "reply.created" => fn ->
        TicketService.reply(ticket!(), %{body: "Hi", is_internal: false})
      end,
      "note.created" => fn ->
        TicketService.reply(ticket!(), %{body: "Psst", is_internal: true})
      end,
      "sla.breached" => fn ->
        ticket!(%{sla_first_response_due_at: minutes_from_now(-60)})
        SlaService.check_breaches()
      end,
      "sla.warning" => fn ->
        ticket!(%{sla_first_response_due_at: minutes_from_now(10)})
        SlaService.check_warnings(30)
      end,
      "ticket.tag_added" => fn -> TicketService.add_tags(ticket!(), [tag!().id]) end,
      "ticket.tag_removed" => fn ->
        tag = tag!()
        {:ok, tagged} = TicketService.add_tags(ticket!(), [tag.id])
        TicketService.remove_tags(tagged, [tag.id])
      end,
      "chat.started" => fn -> chat!() end,
      "chat.assigned" => fn -> ChatSessionService.assign_agent(chat!(), 900) end,
      "chat.message" => fn -> ChatSessionService.send_message(chat!(), "Hi") end,
      "chat.ended" => fn -> ChatSessionService.end_session(chat!()) end
    }
  end

  defp chat! do
    {:ok, _ticket, session} =
      ChatSessionService.start_session(%{guest_name: "Visitor", message: "Hi"})

    session
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

  # :ok when a workflow saved against only `event` logged a run.
  defp workflow_result(event, operation) do
    repo().delete_all(WorkflowLog)
    repo().delete_all(Workflow)
    wf = workflow!(event, [%{"type" => "add_follower", "value" => "77"}])

    try do
      operation.()

      if repo().exists?(from(l in WorkflowLog, where: l.workflow_id == ^wf.id)),
        do: :ok,
        else: "workflow never ran"
    rescue
      error -> "raised #{Exception.message(error)}"
    end
  end

  defp workflow!(trigger_event, actions) do
    %Workflow{}
    |> Workflow.changeset(%{
      name: "on #{trigger_event} #{System.unique_integer([:positive])}",
      trigger_event: trigger_event,
      conditions: %{"all" => []},
      actions: actions,
      is_active: true
    })
    |> repo().insert!()
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

  defp department! do
    %Department{}
    |> Department.changeset(%{name: "Billing #{System.unique_integer([:positive])}"})
    |> repo().insert!()
  end

  defp minutes_from_now(minutes) do
    DateTime.utc_now() |> DateTime.add(minutes * 60, :second) |> DateTime.truncate(:second)
  end

  defp form_props, do: visit(:get, "#{@workflows}/new") |> page() |> Map.fetch!("props")

  defp option_values(options) when is_list(options) do
    Enum.map(options, fn
      %{"value" => value} -> value
      value when is_binary(value) -> value
    end)
  end

  defp option_values(options) when is_map(options), do: Map.keys(options)

  defp visit(method, path, body \\ nil) do
    base =
      case body do
        nil ->
          conn(method, path)

        body ->
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json")
      end

    base
    |> init_test_session(%{})
    |> assign(:current_user, %{id: 1, is_admin: true})
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> Router.call(Router.init([]))
  end

  defp page(conn) do
    assert conn.status == 200, "expected a rendered page, got #{conn.status}: #{conn.resp_body}"
    Jason.decode!(conn.resp_body)
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
