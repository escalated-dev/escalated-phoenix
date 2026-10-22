defmodule Escalated.Services.AutomationRunner do
  @moduledoc """
  Time-based admin rules engine.

  Distinct from `Escalated.Services.WorkflowEngine` (event-driven) and
  Macro (agent-applied manual). See escalated-developer-context/
  domain-model/workflows-automations-macros.md.

  Call `run/1` from a recurring scheduler (`Task.Supervisor.async`,
  Quantum, Oban, or a host-app cron job) — every 5 minutes is the
  portfolio convention.
  """

  import Ecto.Query
  require Logger

  alias Escalated.Schemas.{Automation, Tag, Ticket}
  alias Escalated.Services.{RuleActions, TicketService}

  @doc """
  Evaluate all active automations and apply their actions to matching
  open tickets. Returns the count of (automation × ticket) action
  applications across the entire run.

  Per-action and per-automation failures are caught and logged so a
  single bad rule does not abort the rest.

  ## Required argument

    * `repo` — the Ecto repo module to use (host-app provides this).
  """
  @spec run(module()) :: non_neg_integer()
  def run(repo) when is_atom(repo) do
    if Escalated.Import.Context.importing?(), do: 0, else: do_run(repo)
  end

  defp do_run(repo) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    automations =
      Automation
      |> Automation.active()
      |> repo.all()

    Enum.reduce(automations, 0, fn automation, acc ->
      case run_one(automation, repo) do
        {:ok, n} ->
          acc + n

        {:error, reason} ->
          Logger.warning(
            "Automation ##{automation.id} (#{automation.name}) failed: #{inspect(reason)}"
          )

          acc
      end
    end)
  end

  defp run_one(%Automation{} = automation, repo) do
    tickets = find_matching_tickets(automation, repo)

    Enum.each(tickets, fn ticket ->
      execute_actions(automation, ticket, repo)
    end)

    automation
    |> Automation.changeset(%{last_run_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> repo.update()

    {:ok, length(tickets)}
  rescue
    e -> {:error, e}
  end

  defp find_matching_tickets(%Automation{conditions: conditions}, repo) do
    base =
      from(t in Ticket,
        where: is_nil(t.resolved_at) and is_nil(t.closed_at)
      )

    query =
      Enum.reduce(conditions || [], base, fn condition, q ->
        apply_condition(q, condition)
      end)

    repo.all(query)
    |> Enum.filter(&Escalated.Services.TicketRoutingConditions.matches_all?(conditions, &1))
  end

  # Operator-flipping helper: "hours_since > N" means timestamp <
  # (now - N hours). The DB-level comparison is the inverse of the
  # user-facing operator.
  defp flip(">"), do: :lt
  defp flip(">="), do: :lte
  defp flip("<"), do: :gt
  defp flip("<="), do: :gte
  defp flip("="), do: :eq
  defp flip(_), do: :lt

  defp hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp apply_condition(query, %{"field" => "hours_since_created"} = c) do
    threshold = hours_ago(to_int(c["value"]))
    apply_time_op(query, :inserted_at, flip(c["operator"] || ">"), threshold)
  end

  defp apply_condition(query, %{"field" => "hours_since_updated"} = c) do
    threshold = hours_ago(to_int(c["value"]))
    apply_time_op(query, :updated_at, flip(c["operator"] || ">"), threshold)
  end

  defp apply_condition(query, %{"field" => "hours_since_assigned"} = c) do
    threshold = hours_ago(to_int(c["value"]))

    query
    |> where([t], not is_nil(t.assigned_to))
    |> apply_time_op(:updated_at, flip(c["operator"] || ">"), threshold)
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

  defp apply_condition(query, %{"field" => "assigned", "value" => "assigned"}) do
    where(query, [t], not is_nil(t.assigned_to))
  end

  defp apply_condition(query, %{"field" => "subject_contains", "value" => v}) do
    pattern = "%#{v}%"
    where(query, [t], like(t.subject, ^pattern))
  end

  defp apply_condition(query, %{"field" => "department_id", "value" => id}),
    do: where(query, [t], t.department_id == ^to_int(id))

  # Unknown field — skip silently for forward-compat.
  defp apply_condition(query, _), do: query

  defp apply_time_op(query, field, :lt, threshold),
    do: where(query, [t], field(t, ^field) < ^threshold)

  defp apply_time_op(query, field, :lte, threshold),
    do: where(query, [t], field(t, ^field) <= ^threshold)

  defp apply_time_op(query, field, :gt, threshold),
    do: where(query, [t], field(t, ^field) > ^threshold)

  defp apply_time_op(query, field, :gte, threshold),
    do: where(query, [t], field(t, ^field) >= ^threshold)

  defp apply_time_op(query, field, :eq, threshold),
    do: where(query, [t], field(t, ^field) == ^threshold)

  defp execute_actions(%Automation{actions: actions, id: aid}, %Ticket{} = ticket, repo) do
    # Field changes and notes go through TicketService / AssignmentService so
    # their events, activity rows, workflows and assignment checks run. The
    # ticket is threaded through so each action sees the last one's result.
    Enum.reduce(actions || [], ticket, fn action, current ->
      try do
        case run_action(action, current, aid, repo) do
          {:ok, %Ticket{} = updated} ->
            updated

          {:error, reason} ->
            Logger.warning(
              "Automation ##{aid} action #{inspect(action["type"])} on ticket ##{current.id} failed: #{inspect(reason)}"
            )

            current

          _ ->
            current
        end
      rescue
        e ->
          Logger.warning(
            "Automation ##{aid} action #{inspect(action["type"])} on ticket ##{current.id} failed: #{inspect(e)}"
          )

          current
      end
    end)
  end

  defp run_action(%{"type" => "change_status", "value" => v}, ticket, _aid, _repo),
    do: RuleActions.change_status(ticket, v)

  defp run_action(%{"type" => "change_priority", "value" => v}, ticket, _aid, _repo),
    do: RuleActions.change_priority(ticket, v)

  defp run_action(%{"type" => "assign", "value" => v}, ticket, _aid, _repo),
    do: RuleActions.assign(ticket, v)

  defp run_action(%{"type" => "add_tag", "value" => v}, ticket, _aid, repo) do
    case repo.get_by(Tag, name: to_string(v)) do
      nil ->
        :ok

      %Tag{} = tag ->
        # Phoenix uses an explicit join table; check for existence first
        # to keep this idempotent (matches Laravel syncWithoutDetaching).
        attach_tag(ticket, tag, repo)
    end
  end

  # An automation note is an internal, system-authored note: never shown to
  # the requester. `is_internal` is the only flag Reply casts.
  defp run_action(%{"type" => "add_note", "value" => v}, ticket, _aid, _repo) do
    with {:ok, _reply} <-
           TicketService.reply(ticket, %{body: to_string(v), is_internal: true, is_system: true}) do
      {:ok, ticket}
    end
  end

  defp run_action(_unknown, _ticket, _aid, _repo), do: :ok

  defp attach_tag(ticket, tag, repo) do
    # Match the package's explicit TicketTag schema and migration.
    join_table = Escalated.table_name("ticket_tags")

    repo.insert_all(
      join_table,
      [%{ticket_id: ticket.id, tag_id: tag.id}],
      on_conflict: :nothing
    )

    :ok
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
  defp to_int(_), do: 0
end
