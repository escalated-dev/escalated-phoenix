defmodule Escalated.Services.RuleActionsTest do
  @moduledoc """
  Escalation rules, automations and macros change tickets through
  TicketService / AssignmentService, so the same events, activity rows and
  checks run as for a change an agent makes by hand -- and their notes stay
  internal.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.{
    Automation,
    Department,
    EscalationRule,
    Macro,
    Reply,
    Ticket,
    TicketActivity
  }

  alias Escalated.Services.{AutomationRunner, EscalationService, MacroService}
  alias Escalated.Webhooks

  @events ~w(ticket.updated ticket.status_changed ticket.resolved ticket.escalated
             ticket.priority_changed ticket.department_changed ticket.assigned
             ticket.unassigned reply.created note.created)

  defp repo, do: Escalated.repo()

  setup do
    Application.put_env(:escalated, :webhook_sync, true)
    test_pid = self()

    Application.put_env(:escalated, :webhook_http_client, fn _url, _headers, body ->
      send(test_pid, {:webhook, Jason.decode!(body)["event"]})
      {:ok, %{status: 200, body: "ok"}}
    end)

    on_exit(fn ->
      Application.delete_env(:escalated, :webhook_sync)
      Application.delete_env(:escalated, :webhook_http_client)
    end)

    {:ok, _} =
      Webhooks.create(repo(), %{url: "https://hooks.test/in", events: @events, active: true})

    :ok
  end

  defp ticket!(attrs \\ %{}) do
    %Ticket{}
    |> Ticket.changeset(
      Map.merge(
        %{subject: "Subject", description: "Body", status: "open", priority: "low"},
        attrs
      )
    )
    |> repo().insert!()
  end

  defp department!(name),
    do: repo().insert!(Department.changeset(%Department{}, %{name: name}))

  defp events do
    receive do
      {:webhook, event} -> [event | events()]
    after
      0 -> []
    end
  end

  defp replies(ticket),
    do: repo().all(from(r in Reply, where: r.ticket_id == ^ticket.id, order_by: r.id))

  defp activity(ticket),
    do:
      repo().all(from(a in TicketActivity, where: a.ticket_id == ^ticket.id, order_by: a.id))
      |> Enum.map(& &1.action)

  defp automation!(actions) do
    repo().insert!(
      Automation.changeset(%Automation{}, %{
        name: "auto",
        conditions: [%{"field" => "status", "value" => "open"}],
        actions: actions
      })
    )
  end

  defp escalation!(actions) do
    repo().insert!(
      EscalationRule.changeset(%EscalationRule{}, %{
        name: "esc",
        trigger_type: "cron",
        conditions: [%{"field" => "status", "value" => "open"}],
        actions: actions
      })
    )
  end

  defp macro!(actions),
    do: repo().insert!(Macro.changeset(%Macro{}, %{name: "m", actions: actions, created_by: 7}))

  describe "notes stay internal" do
    test "an automation add_note is an internal system note, not a public reply" do
      ticket = ticket!()
      automation!([%{"type" => "add_note", "value" => "Stale ticket"}])

      AutomationRunner.run(repo())

      assert [%Reply{body: "Stale ticket", is_internal: true, is_system: true}] = replies(ticket)
      received = events()
      assert "note.created" in received
      refute "reply.created" in received
      assert "note_added" in activity(ticket)
    end

    test "a macro add_note is internal and add_reply is public" do
      ticket = ticket!()

      macro =
        macro!([
          %{"type" => "add_note", "value" => "Private"},
          %{"type" => "add_reply", "value" => "Public"}
        ])

      MacroService.apply(repo(), macro, ticket, 7)

      assert [
               %Reply{body: "Private", is_internal: true, author_id: 7},
               %Reply{body: "Public", is_internal: false, author_id: 7}
             ] = replies(ticket)

      received = events()
      assert "note.created" in received
      assert "reply.created" in received
    end

    test "Reply.changeset refuses another port's name for the internal flag" do
      for key <- [:is_internal_note, "is_internal_note"] do
        assert_raise ArgumentError, ~r/use :is_internal/, fn ->
          Reply.changeset(%Reply{}, %{key => true, body: "x", ticket_id: 1})
        end
      end

      assert Reply.changeset(%Reply{}, %{is_internal: true, body: "x", ticket_id: 1}).valid?
    end
  end

  describe "escalation rules go through the ticket and assignment services" do
    test "change_department, assign_to and change_priority fire their events and activity" do
      ticket = ticket!()
      dept = department!("Tier 2")

      escalation!([
        %{"type" => "change_department", "value" => to_string(dept.id)},
        %{"type" => "assign_to", "value" => 42},
        %{"type" => "change_priority", "value" => "urgent"}
      ])

      assert EscalationService.evaluate_rules(repo()) == 1

      updated = repo().get!(Ticket, ticket.id)
      assert updated.department_id == dept.id
      assert updated.assigned_to == 42
      assert updated.priority == "urgent"

      received = events()
      assert "ticket.department_changed" in received
      assert "ticket.assigned" in received
      assert "ticket.priority_changed" in received

      actions = activity(ticket)
      assert "department_changed" in actions
      assert "assigned" in actions
      assert "priority_changed" in actions
    end

    test "escalate transitions the status once, with one ticket.escalated webhook" do
      ticket = ticket!()
      escalation!([%{"type" => "escalate"}])

      EscalationService.evaluate_rules(repo())

      assert repo().get!(Ticket, ticket.id).status == "escalated"
      received = events()
      assert Enum.count(received, &(&1 == "ticket.escalated")) == 1
      assert "ticket.status_changed" in received
      assert "status_changed" in activity(ticket)
      assert "escalated" in activity(ticket)
    end

    test "an unknown department is skipped without breaking later actions" do
      ticket = ticket!()

      escalation!([
        %{"type" => "change_department", "value" => "999999"},
        %{"type" => "change_priority", "value" => "high"}
      ])

      EscalationService.evaluate_rules(repo())

      updated = repo().get!(Ticket, ticket.id)
      assert is_nil(updated.department_id)
      assert updated.priority == "high"
    end
  end

  describe "automation field actions go through the services" do
    test "change_status to resolved stamps resolved_at and fires the status events" do
      ticket = ticket!()

      automation!([
        %{"type" => "assign", "value" => 5},
        %{"type" => "change_status", "value" => "resolved"}
      ])

      AutomationRunner.run(repo())

      updated = repo().get!(Ticket, ticket.id)
      assert updated.status == "resolved"
      assert updated.resolved_at
      assert updated.assigned_to == 5

      received = events()
      assert "ticket.status_changed" in received
      assert "ticket.resolved" in received
      assert "ticket.assigned" in received
    end

    test "a change to the value the ticket already has fires nothing" do
      ticket!(%{priority: "high"})
      automation!([%{"type" => "change_priority", "value" => "high"}])

      AutomationRunner.run(repo())

      refute "ticket.priority_changed" in events()
    end
  end

  describe "macro field actions go through the services" do
    test "status, priority and assign are attributed to the applying agent" do
      ticket = ticket!()

      macro =
        macro!([
          %{"type" => "set_status", "value" => "in_progress"},
          %{"type" => "change_priority", "value" => "high"},
          %{"type" => "assign", "value" => 7}
        ])

      result = MacroService.apply(repo(), macro, ticket, 7)

      assert %Ticket{status: "in_progress", priority: "high", assigned_to: 7} = result

      causers =
        repo().all(
          from(a in TicketActivity,
            where:
              a.ticket_id == ^ticket.id and
                a.action in ["status_changed", "priority_changed", "assigned"],
            select: {a.action, a.causer_id}
          )
        )

      assert Enum.sort(causers) == [
               {"assigned", 7},
               {"priority_changed", 7},
               {"status_changed", 7}
             ]

      received = events()
      assert "ticket.status_changed" in received
      assert "ticket.priority_changed" in received
      assert "ticket.assigned" in received
    end
  end
end
