defmodule Escalated.Services.WorkflowEngine do
  @moduledoc "Workflow automation engine with condition evaluation and action execution"

  @operators ~w(equals not_equals contains not_contains starts_with ends_with greater_than less_than greater_or_equal less_or_equal is_empty is_not_empty)
  @action_types ~w(change_status assign_agent change_priority add_tag remove_tag set_department add_note send_webhook set_type delay add_follower send_notification)
  @trigger_events ~w(ticket.created ticket.updated ticket.status_changed ticket.assigned ticket.priority_changed ticket.tagged ticket.department_changed reply.created reply.agent_reply sla.warning sla.breached ticket.reopened)

  def operators, do: @operators
  def action_types, do: @action_types
  def trigger_events, do: @trigger_events

  def evaluate_conditions(%{"all" => conditions}, ticket) when is_list(conditions) do
    Enum.all?(conditions, &evaluate_single(&1, ticket))
  end
  def evaluate_conditions(%{"any" => conditions}, ticket) when is_list(conditions) do
    Enum.any?(conditions, &evaluate_single(&1, ticket))
  end
  def evaluate_conditions(conditions, ticket) when is_list(conditions) do
    Enum.all?(conditions, &evaluate_single(&1, ticket))
  end
  def evaluate_conditions(condition, ticket) when is_map(condition) do
    evaluate_single(condition, ticket)
  end
  def evaluate_conditions(_, _), do: false

  def dry_run(conditions, actions, ticket) do
    matched = evaluate_conditions(conditions, ticket)
    previews = Enum.map(actions, fn a ->
      %{type: a["type"], value: interpolate(a["value"] || "", ticket), would_execute: matched}
    end)
    %{matched: matched, actions: previews}
  end

  def interpolate(text, ticket) when is_binary(text) do
    Regex.replace(~r/\{\{(\w+)\}\}/, text, fn _, var ->
      case var do
        "reference" -> Map.get(ticket, :reference, "")
        "subject" -> Map.get(ticket, :subject, "")
        "status" -> Map.get(ticket, :status, "")
        "priority" -> Map.get(ticket, :priority, "")
        _ -> "{{#{var}}}"
      end
    end)
  end
  def interpolate(text, _), do: to_string(text)

  defp evaluate_single(%{"field" => field, "operator" => op, "value" => expected}, ticket) do
    actual = resolve_field(field, ticket)
    apply_operator(op, to_string(actual), to_string(expected))
  end
  defp evaluate_single(_, _), do: false

  defp resolve_field("status", t), do: Map.get(t, :status)
  defp resolve_field("priority", t), do: Map.get(t, :priority)
  defp resolve_field("subject", t), do: Map.get(t, :subject)
  defp resolve_field("description", t), do: Map.get(t, :description)
  defp resolve_field("channel", t), do: Map.get(t, :channel)
  defp resolve_field("ticket_type", t), do: Map.get(t, :ticket_type)
  defp resolve_field("assigned_to", t), do: Map.get(t, :assigned_to)
  defp resolve_field(_, _), do: nil

  defp apply_operator("equals", a, e), do: a == e
  defp apply_operator("not_equals", a, e), do: a != e
  defp apply_operator("contains", a, e), do: String.contains?(a, e)
  defp apply_operator("not_contains", a, e), do: not String.contains?(a, e)
  defp apply_operator("starts_with", a, e), do: String.starts_with?(a, e)
  defp apply_operator("ends_with", a, e), do: String.ends_with?(a, e)
  defp apply_operator("is_empty", a, _), do: String.trim(a) == ""
  defp apply_operator("is_not_empty", a, _), do: String.trim(a) != ""
  defp apply_operator("greater_than", a, e), do: parse_float(a) > parse_float(e)
  defp apply_operator("less_than", a, e), do: parse_float(a) < parse_float(e)
  defp apply_operator("greater_or_equal", a, e), do: parse_float(a) >= parse_float(e)
  defp apply_operator("less_or_equal", a, e), do: parse_float(a) <= parse_float(e)
  defp apply_operator(_, _, _), do: false

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0.0
    end
  end
end
