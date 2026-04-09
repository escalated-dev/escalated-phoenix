defmodule Escalated.Services.WorkflowEngineTest do
  use ExUnit.Case, async: true
  alias Escalated.Services.WorkflowEngine

  @ticket %{status: "open", priority: "medium", subject: "Test billing issue", description: "desc", reference: "ESC-001"}

  test "evaluates AND conditions" do
    conditions = %{"all" => [
      %{"field" => "status", "operator" => "equals", "value" => "open"},
      %{"field" => "priority", "operator" => "equals", "value" => "medium"}
    ]}
    assert WorkflowEngine.evaluate_conditions(conditions, @ticket) == true
  end

  test "evaluates OR conditions" do
    conditions = %{"any" => [
      %{"field" => "status", "operator" => "equals", "value" => "closed"},
      %{"field" => "status", "operator" => "equals", "value" => "open"}
    ]}
    assert WorkflowEngine.evaluate_conditions(conditions, @ticket) == true
  end

  test "contains operator" do
    conditions = %{"all" => [%{"field" => "subject", "operator" => "contains", "value" => "billing"}]}
    assert WorkflowEngine.evaluate_conditions(conditions, @ticket) == true
  end

  test "is_empty operator" do
    ticket = %{description: ""}
    conditions = %{"all" => [%{"field" => "description", "operator" => "is_empty", "value" => ""}]}
    assert WorkflowEngine.evaluate_conditions(conditions, ticket) == true
  end

  test "interpolate variables" do
    result = WorkflowEngine.interpolate("Ticket {{reference}} is {{status}}", @ticket)
    assert result == "Ticket ESC-001 is open"
  end

  test "dry_run returns preview" do
    conditions = %{"all" => [%{"field" => "status", "operator" => "equals", "value" => "open"}]}
    actions = [%{"type" => "add_note", "value" => "Note for {{reference}}"}]
    result = WorkflowEngine.dry_run(conditions, actions, @ticket)
    assert result.matched == true
    assert hd(result.actions).value == "Note for ESC-001"
  end
end
