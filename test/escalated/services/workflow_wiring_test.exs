defmodule Escalated.Services.WorkflowWiringTest do
  @moduledoc """
  End-to-end proof that the Workflow engine is actually wired into the
  ticket lifecycle: creating a ticket / replying / changing status now
  fires configured Workflows, writes a WorkflowLog, honours conditions,
  and is guarded against runaway re-entrancy — none of which happened
  before `TicketService` invoked `WorkflowRunner.run_for_event/2`.
  """
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{Reply, Ticket, Workflow, WorkflowLog}
  alias Escalated.Services.TicketService

  defp repo, do: Escalated.repo()

  defp insert_workflow!(attrs) do
    {:ok, wf} =
      %Workflow{}
      |> Workflow.changeset(
        Map.merge(
          %{name: "WF", conditions: %{}, actions: [], is_active: true},
          attrs
        )
      )
      |> repo().insert()

    wf
  end

  defp insert_ticket!(attrs \\ %{}) do
    {:ok, t} =
      %Ticket{}
      |> Ticket.changeset(Map.merge(%{subject: "S", description: "D", priority: "medium"}, attrs))
      |> repo().insert()

    t
  end

  describe "ticket.created trigger" do
    test "a matching workflow fires and its action mutates the ticket" do
      wf =
        insert_workflow!(%{
          trigger_event: "ticket.created",
          actions: [%{"type" => "change_priority", "value" => "high"}]
        })

      {:ok, ticket} = TicketService.create(%{subject: "Refund please", description: "help"})

      # The action ran after insert, so re-read from the DB.
      assert repo().get(Ticket, ticket.id).priority == "high"

      # And a log row was written (proves the schema/table reconciliation).
      log = repo().get_by(WorkflowLog, workflow_id: wf.id, ticket_id: ticket.id)
      assert log.trigger_event == "ticket.created"
      assert log.conditions_matched == true
      assert log.status == "success"
      refute is_nil(log.completed_at)
    end

    test "a non-matching workflow is skipped (action does not run)" do
      insert_workflow!(%{
        trigger_event: "ticket.created",
        conditions: %{
          "all" => [%{"field" => "status", "operator" => "equals", "value" => "closed"}]
        },
        actions: [%{"type" => "change_priority", "value" => "urgent"}]
      })

      {:ok, ticket} = TicketService.create(%{subject: "Normal", description: "help"})

      assert repo().get(Ticket, ticket.id).priority == "medium"

      log = repo().get_by(WorkflowLog, ticket_id: ticket.id)
      assert log.conditions_matched == false
      assert log.status == "skipped"
    end

    test "an inactive workflow never fires" do
      insert_workflow!(%{
        trigger_event: "ticket.created",
        is_active: false,
        actions: [%{"type" => "change_priority", "value" => "urgent"}]
      })

      {:ok, ticket} = TicketService.create(%{subject: "X", description: "help"})

      assert repo().get(Ticket, ticket.id).priority == "medium"
      assert repo().all(WorkflowLog) == []
    end
  end

  describe "reply.created trigger" do
    test "a public reply fires the workflow" do
      insert_workflow!(%{
        trigger_event: "reply.created",
        actions: [%{"type" => "change_status", "value" => "in_progress"}]
      })

      ticket = insert_ticket!()

      {:ok, _reply} =
        TicketService.reply(ticket, %{body: "on it", is_internal: false, author_id: nil})

      assert repo().get(Ticket, ticket.id).status == "in_progress"
    end

    test "an internal note does NOT fire the reply.created workflow" do
      insert_workflow!(%{
        trigger_event: "reply.created",
        actions: [%{"type" => "change_status", "value" => "in_progress"}]
      })

      ticket = insert_ticket!()

      {:ok, _reply} =
        TicketService.reply(ticket, %{body: "private", is_internal: true, author_id: nil})

      assert repo().get(Ticket, ticket.id).status == "open"
      assert repo().all(WorkflowLog) == []
    end
  end

  describe "ticket.status_changed trigger" do
    test "a status transition fires the workflow" do
      insert_workflow!(%{
        trigger_event: "ticket.status_changed",
        actions: [%{"type" => "change_priority", "value" => "high"}]
      })

      ticket = insert_ticket!()

      {:ok, _} = TicketService.transition_status(ticket, "resolved")

      reloaded = repo().get(Ticket, ticket.id)
      assert reloaded.status == "resolved"
      assert reloaded.priority == "high"
    end
  end

  describe "re-entrancy guard" do
    test "a reply-inserting workflow does not recurse infinitely" do
      # insert_canned_reply creates a PUBLIC reply, which would itself
      # re-trigger reply.created without the guard.
      insert_workflow!(%{
        trigger_event: "reply.created",
        actions: [%{"type" => "insert_canned_reply", "value" => "Auto-ack for {{reference}}"}]
      })

      ticket = insert_ticket!()

      {:ok, _reply} =
        TicketService.reply(ticket, %{body: "customer msg", is_internal: false, author_id: nil})

      # Exactly the original reply + one canned reply — no runaway loop.
      import Ecto.Query
      reply_count = repo().aggregate(from(r in Reply, where: r.ticket_id == ^ticket.id), :count)
      assert reply_count == 2

      # Only the top-level run touched the engine; the nested reply was suppressed.
      assert repo().aggregate(WorkflowLog, :count) == 1
    end
  end

  describe "engine failures never break the mutation" do
    test "an action that fails still lets the ticket operation succeed" do
      insert_workflow!(%{
        trigger_event: "ticket.created",
        # invalid status → transition_status returns {:error, changeset}
        actions: [%{"type" => "change_status", "value" => "not_a_real_status"}]
      })

      assert {:ok, ticket} = TicketService.create(%{subject: "Still works", description: "help"})
      assert repo().get(Ticket, ticket.id)
    end
  end
end
