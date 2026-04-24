defmodule Escalated.Services.WorkflowExecutorTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.WorkflowExecutor

  # Pure-function tests. Full integration with Ecto repo is verified
  # in the consuming WorkflowRunner test in a follow-up PR once a test
  # repo is configured.

  describe "parse_actions/1" do
    test "returns [] for nil" do
      assert WorkflowExecutor.parse_actions(nil) == []
    end

    test "returns [] for empty string" do
      assert WorkflowExecutor.parse_actions("") == []
    end

    test "returns [] for malformed JSON" do
      assert WorkflowExecutor.parse_actions("not json") == []
    end

    test "returns [] for non-array JSON" do
      assert WorkflowExecutor.parse_actions(~s({"type":"change_priority"})) == []
    end

    test "returns parsed list for valid action array" do
      json = ~s([{"type":"change_priority","value":"high"},{"type":"add_note","value":"go"}])
      result = WorkflowExecutor.parse_actions(json)
      assert [%{"type" => "change_priority", "value" => "high"},
              %{"type" => "add_note", "value" => "go"}] = result
    end

    test "passes pre-decoded list through unchanged" do
      input = [%{"type" => "change_priority", "value" => "high"}]
      assert WorkflowExecutor.parse_actions(input) == input
    end
  end

  describe "ticket_to_map/1" do
    test "extracts the interpolator-facing fields" do
      ticket = %{
        reference: "ESC-42",
        subject: "Help",
        status: "open",
        priority: "medium",
        some_other_field: "ignored"
      }

      assert WorkflowExecutor.ticket_to_map(ticket) == %{
               reference: "ESC-42",
               subject: "Help",
               status: "open",
               priority: "medium"
             }
    end

    test "defaults missing fields to empty string" do
      assert WorkflowExecutor.ticket_to_map(%{}) == %{
               reference: "",
               subject: "",
               status: "",
               priority: ""
             }
    end
  end

  describe "dispatch_action/2 — non-DB action validation" do
    test "returns :missing_type when action lacks :type key" do
      assert {:error, "unknown", :missing_type} =
               WorkflowExecutor.dispatch_action(%{}, %{"value" => "x"})
    end

    test "returns :blank_value for change_priority with empty value" do
      assert {:error, "change_priority", :blank_value} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1, status: "open", priority: "low"},
                 %{"type" => "change_priority", "value" => ""}
               )
    end

    test "returns :blank_value for change_status with empty value" do
      assert {:error, "change_status", :blank_value} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1, status: "open"},
                 %{"type" => "change_status", "value" => ""}
               )
    end

    test "returns :invalid_agent_id for non-numeric assign_agent" do
      assert {:error, "assign_agent", :invalid_agent_id} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "assign_agent", "value" => "not-a-number"}
               )
    end

    test "returns :invalid_agent_id for zero/negative assign_agent" do
      assert {:error, "assign_agent", :invalid_agent_id} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "assign_agent", "value" => "0"}
               )
    end

    test "returns :invalid_department for non-numeric set_department" do
      assert {:error, "set_department", :invalid_department} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "set_department", "value" => "abc"}
               )
    end

    test "returns :blank_value for add_note with empty value" do
      assert {:error, "add_note", :blank_value} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "add_note", "value" => ""}
               )
    end

    test "returns :blank_value for insert_canned_reply with empty value" do
      assert {:error, "insert_canned_reply", :blank_value} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "insert_canned_reply", "value" => ""}
               )
    end

    test "returns :unknown for future action types" do
      assert {:error, "future_action", :unknown} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "future_action", "value" => "x"}
               )
    end

    test "dispatch_action on delay returns :handled_in_execute (usage error)" do
      assert {:error, "delay", :handled_in_execute} =
               WorkflowExecutor.dispatch_action(
                 %{id: 1},
                 %{"type" => "delay", "value" => "60"}
               )
    end
  end

  describe "handle_delay/4 — non-DB validation" do
    test "returns :no_workflow_id when workflow_id is missing from opts" do
      assert {:error, "delay", :no_workflow_id} =
               WorkflowExecutor.handle_delay(
                 %{id: 1},
                 %{"type" => "delay", "value" => "60"},
                 [],
                 []
               )
    end

    test "returns :invalid_minutes when value is not numeric" do
      assert {:error, "delay", :invalid_minutes} =
               WorkflowExecutor.handle_delay(
                 %{id: 1},
                 %{"type" => "delay", "value" => "abc"},
                 [],
                 workflow_id: 7
               )
    end

    test "returns :invalid_minutes when value is zero" do
      assert {:error, "delay", :invalid_minutes} =
               WorkflowExecutor.handle_delay(
                 %{id: 1},
                 %{"type" => "delay", "value" => "0"},
                 [],
                 workflow_id: 7
               )
    end

    test "returns :invalid_minutes when value is negative" do
      assert {:error, "delay", :invalid_minutes} =
               WorkflowExecutor.handle_delay(
                 %{id: 1},
                 %{"type" => "delay", "value" => "-1"},
                 [],
                 workflow_id: 7
               )
    end
  end

  describe "execute/2 shape" do
    test "returns {:ok, [], []} for nil actions" do
      assert {:ok, [], []} = WorkflowExecutor.execute(%{id: 1}, nil)
    end

    test "returns parsed actions and per-action results" do
      # All blank values → each action returns its own :blank_value
      # error without ever touching the DB.
      json = ~s([
        {"type":"change_priority","value":""},
        {"type":"add_note","value":""},
        {"type":"future","value":"x"}
      ])

      {:ok, actions, results} = WorkflowExecutor.execute(%{id: 1}, json)
      assert length(actions) == 3
      assert length(results) == 3
      assert Enum.at(results, 0) == {:error, "change_priority", :blank_value}
      assert Enum.at(results, 1) == {:error, "add_note", :blank_value}
      assert Enum.at(results, 2) == {:error, "future", :unknown}
    end
  end

  describe "execute/3 delay short-circuits remaining actions" do
    test "when delay has :no_workflow_id, remaining actions are skipped" do
      json = ~s([
        {"type":"delay","value":"5"},
        {"type":"change_priority","value":"high"}
      ])

      {:ok, actions, results} = WorkflowExecutor.execute(%{id: 1}, json)
      assert length(actions) == 2
      assert Enum.at(results, 0) == {:error, "delay", :no_workflow_id}
      assert Enum.at(results, 1) == {:error, "change_priority", :skipped_after_delay}
    end

    test "when delay has :invalid_minutes, remaining actions are skipped" do
      json = ~s([
        {"type":"change_priority","value":""},
        {"type":"delay","value":"abc"},
        {"type":"add_note","value":"after wait"}
      ])

      {:ok, _actions, results} =
        WorkflowExecutor.execute(%{id: 1}, json, workflow_id: 9)

      assert Enum.at(results, 0) == {:error, "change_priority", :blank_value}
      assert Enum.at(results, 1) == {:error, "delay", :invalid_minutes}
      assert Enum.at(results, 2) == {:error, "add_note", :skipped_after_delay}
    end
  end

  describe "module interface" do
    test "execute/2 is defined" do
      assert function_exported?(WorkflowExecutor, :execute, 2)
    end

    test "execute/3 is defined" do
      assert function_exported?(WorkflowExecutor, :execute, 3)
    end

    test "parse_actions/1 is defined" do
      assert function_exported?(WorkflowExecutor, :parse_actions, 1)
    end

    test "dispatch_action/2 is defined" do
      assert function_exported?(WorkflowExecutor, :dispatch_action, 2)
    end

    test "handle_delay/4 is defined" do
      assert function_exported?(WorkflowExecutor, :handle_delay, 4)
    end

    test "run_due_delayed_actions/0 is defined" do
      assert function_exported?(WorkflowExecutor, :run_due_delayed_actions, 0)
    end

    test "resolve_tag_id/1 is defined" do
      assert function_exported?(WorkflowExecutor, :resolve_tag_id, 1)
    end
  end
end
