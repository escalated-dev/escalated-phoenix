defmodule Escalated.Services.WorkflowRunnerTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.WorkflowRunner

  # Pure-function / interface tests. Full integration with Ecto repo
  # is verified once a test repo is configured — see TicketServiceTest
  # for the equivalent pattern today.

  describe "evaluate/2" do
    test "nil conditions match everything" do
      assert WorkflowRunner.evaluate(nil, %{"status" => "open"}) == true
    end

    test "empty-map conditions match everything" do
      assert WorkflowRunner.evaluate(%{}, %{"status" => "open"}) == true
    end

    test "empty-list conditions match everything" do
      assert WorkflowRunner.evaluate([], %{"status" => "open"}) == true
    end

    test "matching 'all' returns true" do
      conditions = %{
        "all" => [%{"field" => "status", "operator" => "equals", "value" => "open"}]
      }

      assert WorkflowRunner.evaluate(conditions, %{"status" => "open"}) == true
    end

    test "non-matching 'all' returns false" do
      conditions = %{
        "all" => [%{"field" => "status", "operator" => "equals", "value" => "closed"}]
      }

      assert WorkflowRunner.evaluate(conditions, %{"status" => "open"}) == false
    end
  end

  describe "ticket_to_condition_map/1" do
    test "stringifies known keys and drops nils" do
      ticket = %{
        id: 7,
        subject: "Help",
        status: "open",
        priority: "medium",
        description: nil,
        some_ignored_field: "x"
      }

      map = WorkflowRunner.ticket_to_condition_map(ticket)
      assert map["id"] == "7"
      assert map["subject"] == "Help"
      assert map["status"] == "open"
      assert map["priority"] == "medium"
      refute Map.has_key?(map, "description")
      refute Map.has_key?(map, "some_ignored_field")
    end

    test "empty ticket yields empty map" do
      assert WorkflowRunner.ticket_to_condition_map(%{}) == %{}
    end

    test "stringifies integers and atoms" do
      ticket = %{id: 42, assigned_to: 99}
      map = WorkflowRunner.ticket_to_condition_map(ticket)
      assert map["id"] == "42"
      assert map["assigned_to"] == "99"
    end
  end

  describe "module interface" do
    test "run_for_event/2 is defined" do
      assert function_exported?(WorkflowRunner, :run_for_event, 2)
    end

    test "evaluate/2 is defined" do
      assert function_exported?(WorkflowRunner, :evaluate, 2)
    end

    test "ticket_to_condition_map/1 is defined" do
      assert function_exported?(WorkflowRunner, :ticket_to_condition_map, 1)
    end
  end
end
