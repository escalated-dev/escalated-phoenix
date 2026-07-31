defmodule Escalated.Services.WorkflowRunner do
  @moduledoc """
  Orchestrates evaluation + execution of Workflows for a given trigger
  event.

  For each active Workflow matching the trigger (in `position` order),
  evaluates conditions via `Escalated.Services.WorkflowEngine` and, if
  matched, dispatches to `Escalated.Services.WorkflowExecutor`. Writes
  a `WorkflowLog` row per Workflow considered. Honors `stop_on_match`.

  Executor failures are caught so one misbehaving workflow never blocks
  the rest — the error is stamped on the log row via `error_message`.

  Mirrors the NestJS reference `workflow-runner.service.ts`.
  """

  alias Escalated.Schemas.{Workflow, WorkflowLog}
  alias Escalated.Services.{WorkflowEngine, WorkflowExecutor}
  import Ecto.Query
  require Logger

  @type execution_outcome ::
          {:matched_and_executed, [any()]}
          | {:matched_and_failed, String.t()}
          | :unmatched

  @doc """
  Run workflows matching the given trigger event against a ticket.

  Returns a list of `{workflow_id, outcome}` tuples in execution order.
  `outcome` is one of `:unmatched`, `{:matched_and_executed, results}`,
  or `{:matched_and_failed, reason}`.
  """
  @spec run_for_event(String.t(), map()) :: [{integer(), execution_outcome()}]
  def run_for_event(trigger_event, ticket) do
    workflows = load_active_workflows(trigger_event)
    condition_map = ticket_to_condition_map(ticket)

    Enum.reduce_while(workflows, [], fn wf, acc ->
      {log, outcome} = process_workflow(wf, trigger_event, ticket, condition_map)
      persist_log(log)
      new_acc = [{wf.id, outcome} | acc]

      case outcome do
        {:matched_and_executed, _} when wf.stop_on_match -> {:halt, new_acc}
        _ -> {:cont, new_acc}
      end
    end)
    |> Enum.reverse()
  end

  defp load_active_workflows(trigger_event) do
    repo = Escalated.repo()

    from(w in Workflow,
      where: w.trigger_event == ^trigger_event and w.is_active == true,
      order_by: [asc: w.position]
    )
    |> repo.all()
  end

  defp process_workflow(%Workflow{} = wf, trigger_event, ticket, condition_map) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    matched = evaluate(wf.conditions, condition_map)

    base_attrs = %{
      workflow_id: wf.id,
      ticket_id: ticket.id,
      trigger_event: trigger_event,
      conditions_matched: matched,
      started_at: started_at
    }

    if matched do
      case execute_safely(ticket, wf) do
        {:ok, results} ->
          attrs =
            Map.merge(base_attrs, %{
              status: "success",
              actions_executed: normalize_results(results),
              completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          {attrs, {:matched_and_executed, results}}

        {:error, reason} ->
          Logger.error(
            "[WorkflowRunner] workflow ##{wf.id} (#{wf.name}) failed on ticket ##{ticket.id}: #{reason}"
          )

          attrs =
            Map.merge(base_attrs, %{
              status: "failed",
              error_message: reason,
              completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          {attrs, {:matched_and_failed, reason}}
      end
    else
      {Map.put(base_attrs, :status, "skipped"), :unmatched}
    end
  end

  @doc false
  @spec evaluate(map() | list() | nil, map()) :: boolean()
  def evaluate(nil, _), do: true
  def evaluate(conds, _) when map_size(conds) == 0, do: true
  def evaluate([], _), do: true

  def evaluate(conditions, condition_map),
    do: WorkflowEngine.evaluate_conditions(conditions, condition_map)

  defp execute_safely(ticket, %Workflow{} = wf) do
    {:ok, _actions, results} = WorkflowExecutor.execute(ticket, wf.actions)
    {:ok, results}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp persist_log(attrs) do
    repo = Escalated.repo()

    %WorkflowLog{}
    |> WorkflowLog.changeset(attrs)
    |> repo.insert()
  end

  # WorkflowExecutor returns tuples like {:ok, type} / {:error, type, reason}.
  # Serialize into plain maps for the JSON column.
  defp normalize_results(results) do
    Enum.map(results, fn
      {:ok, type} ->
        %{"type" => type, "status" => "ok"}

      {:error, type, reason} ->
        %{"type" => type, "status" => "error", "reason" => to_string(reason)}

      other ->
        %{"raw" => inspect(other)}
    end)
  end

  @doc false
  @spec ticket_to_condition_map(map()) :: map()
  def ticket_to_condition_map(ticket) do
    keys = [
      :id,
      :subject,
      :description,
      :reference,
      :status,
      :priority,
      :channel,
      :ticket_type,
      :assigned_to,
      :department_id,
      :requester_id,
      :guest_name,
      :guest_email
    ]

    Enum.reduce(keys, %{}, fn key, acc ->
      value = Map.get(ticket, key)

      if is_nil(value) do
        acc
      else
        Map.put(acc, to_string(key), to_string(value))
      end
    end)
  end
end
