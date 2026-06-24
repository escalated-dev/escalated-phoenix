defmodule Escalated.Services.EscalationService do
  @moduledoc """
  Time-based escalation rules engine.

  Evaluates active `Escalated.Schemas.EscalationRule` rows against open
  tickets and applies their actions (escalate, change priority, assign,
  change department). Mirrors the Laravel `EscalationService`.

  Distinct from `Escalated.Services.AutomationRunner` (general time-based
  automations), `Escalated.Services.WorkflowEngine` (event-driven), and
  Macro (agent-applied manual). Call `evaluate_rules/1` from a recurring
  scheduler — every 5 minutes is the portfolio convention (see the
  `mix escalated.evaluate_escalations` task).
  """
  import Ecto.Query
  require Logger

  alias Escalated.Schemas.{EscalationRule, Ticket, TicketActivity}

  @doc """
  Evaluate all active escalation rules and apply their actions to
  matching open tickets. Returns the count of (rule × ticket)
  applications across the run. Per-rule failures are caught and logged so
  a single bad rule does not abort the rest.

  ## Required argument

    * `repo` — the Ecto repo module to use (host-app provides this).
  """
  @spec evaluate_rules(module()) :: non_neg_integer()
  def evaluate_rules(repo) when is_atom(repo) do
    rules =
      EscalationRule
      |> EscalationRule.active()
      |> repo.all()

    Enum.reduce(rules, 0, fn rule, acc ->
      case evaluate_one(rule, repo) do
        {:ok, n} ->
          acc + n

        {:error, reason} ->
          Logger.warning("Escalation rule ##{rule.id} (#{rule.name}) failed: #{inspect(reason)}")

          acc
      end
    end)
  end

  defp evaluate_one(%EscalationRule{} = rule, repo) do
    tickets = find_matching_tickets(rule, repo)

    Enum.each(tickets, fn ticket ->
      execute_actions(rule, ticket, repo)
    end)

    {:ok, length(tickets)}
  rescue
    e -> {:error, e}
  end

  defp find_matching_tickets(%EscalationRule{conditions: conditions}, repo) do
    query =
      Enum.reduce(conditions || [], Ticket.by_open(), fn condition, q ->
        apply_condition(q, condition)
      end)

    repo.all(query)
  end

  defp hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp apply_condition(query, %{"field" => "status", "value" => v}) do
    where(query, [t], t.status == ^v)
  end

  defp apply_condition(query, %{"field" => "priority", "value" => v}) do
    where(query, [t], t.priority == ^v)
  end

  defp apply_condition(query, %{"field" => "assigned", "value" => "unassigned"}) do
    where(query, [t], is_nil(t.assigned_to))
  end

  defp apply_condition(query, %{"field" => "assigned"}) do
    where(query, [t], not is_nil(t.assigned_to))
  end

  defp apply_condition(query, %{"field" => "age_hours", "value" => v}) do
    where(query, [t], t.inserted_at <= ^hours_ago(to_int(v)))
  end

  defp apply_condition(query, %{"field" => "no_response_hours", "value" => v}) do
    query
    |> where([t], is_nil(t.first_response_at))
    |> where([t], t.inserted_at <= ^hours_ago(to_int(v)))
  end

  defp apply_condition(query, %{"field" => "sla_breached"}) do
    Ticket.breached_sla(query)
  end

  defp apply_condition(query, %{"field" => "department_id", "value" => v}) do
    where(query, [t], t.department_id == ^to_int(v))
  end

  # Unknown field — skip silently for forward-compat.
  defp apply_condition(query, _), do: query

  defp execute_actions(%EscalationRule{actions: actions, name: name}, %Ticket{} = ticket, repo) do
    Enum.each(actions || [], fn action ->
      try do
        run_action(action, ticket, repo)
      rescue
        e ->
          Logger.warning(
            "Escalation action #{inspect(action["type"])} on ticket ##{ticket.id} failed: #{inspect(e)}"
          )
      end
    end)

    maybe_log_escalation(actions || [], ticket, name, repo)
  end

  defp run_action(%{"type" => "escalate"}, ticket, repo) do
    ticket |> Ticket.changeset(%{status: "escalated"}) |> repo.update()
  end

  defp run_action(%{"type" => "change_priority", "value" => v}, ticket, repo) do
    ticket |> Ticket.changeset(%{priority: to_string(v)}) |> repo.update()
  end

  defp run_action(%{"type" => "assign_to", "value" => v}, ticket, repo) do
    ticket |> Ticket.changeset(%{assigned_to: v}) |> repo.update()
  end

  defp run_action(%{"type" => "change_department", "value" => v}, ticket, repo) do
    ticket |> Ticket.changeset(%{department_id: to_int(v)}) |> repo.update()
  end

  defp run_action(_unknown, _ticket, _repo), do: :ok

  # Mirrors Laravel's TicketEscalated event: when a rule carries an
  # `escalate` action, record one activity-log entry per affected ticket.
  defp maybe_log_escalation(actions, ticket, rule_name, repo) do
    if Enum.any?(actions, &(&1["type"] == "escalate")) do
      %TicketActivity{}
      |> TicketActivity.changeset(%{
        ticket_id: ticket.id,
        action: "escalated",
        description: "Escalation rule: #{rule_name}",
        details: %{"rule" => rule_name}
      })
      |> repo.insert()
    end

    :ok
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(_), do: 0
end
