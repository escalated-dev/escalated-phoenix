defmodule Escalated.Services.WorkflowListenerTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.WorkflowListener

  # WorkflowListener is a thin wrapper around WorkflowRunner.run_for_event/2.
  # Full integration with Ecto repo is verified in the WorkflowRunner test
  # once a test repo is configured. These tests focus on the mapping API
  # surface (module interface checks) and the fire/2 argument validation.

  describe "fire/2" do
    test "returns :ok for a valid trigger + ticket map" do
      assert WorkflowListener.fire("ticket.created", %{id: 1}) == :ok
    end

    test "returns :ok silently on non-binary trigger" do
      assert WorkflowListener.fire(:ticket_created, %{id: 1}) == :ok
    end

    test "returns :ok silently on non-map ticket" do
      assert WorkflowListener.fire("ticket.created", nil) == :ok
    end

    test "returns :ok silently on both-invalid" do
      assert WorkflowListener.fire(nil, nil) == :ok
    end
  end

  describe "reply_created/1" do
    test "accepts a reply with embedded ticket" do
      assert WorkflowListener.reply_created(%{ticket: %{id: 1}}) == :ok
    end

    test "returns :ok without an embedded ticket" do
      assert WorkflowListener.reply_created(%{ticket_id: 1}) == :ok
      assert WorkflowListener.reply_created(%{}) == :ok
      assert WorkflowListener.reply_created(nil) == :ok
    end
  end

  describe "module interface (per-event helpers)" do
    for helper <- [
          :ticket_created,
          :ticket_updated,
          :ticket_status_changed,
          :ticket_priority_changed,
          :ticket_assigned,
          :ticket_reopened,
          :ticket_tagged,
          :ticket_department_changed,
          :reply_created,
          :sla_breached,
          :sla_warning
        ] do
      test "#{helper}/1 is defined" do
        assert function_exported?(WorkflowListener, unquote(helper), 1)
      end
    end

    test "fire/2 is defined" do
      assert function_exported?(WorkflowListener, :fire, 2)
    end
  end
end
