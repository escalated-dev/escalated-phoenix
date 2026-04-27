defmodule Escalated.Services.WorkflowExecutor do
  @moduledoc """
  Performs the side-effects dictated by a matched `Workflow`.

  Distinct from `Escalated.Services.WorkflowEngine`, which only evaluates
  conditions. This module parses the JSON action array stored on
  `workflow.actions` and dispatches each entry against `TicketService` /
  `AssignmentService` / `Escalated.repo/0`.

  ## Action catalog

  `change_priority`, `change_status`, `assign_agent`, `set_department`,
  `add_tag`, `remove_tag`, `add_note`, `insert_canned_reply`, `delay`.

  Mirrors the NestJS reference impl in
  `escalated-nestjs/src/services/workflow-executor.service.ts`.

  ## Delay semantics

  A `delay` action with numeric `value` (minutes) splits the run: actions
  before `delay` run inline, remaining actions become one
  `Escalated.Schemas.DelayedAction` row each with `execute_at = now + N`
  minutes. `run_due_delayed_actions/0` sweeps pending rows and
  re-dispatches them. Requires `workflow_id` in the options — without
  it, the delay action returns `{:error, "delay", :no_workflow_id}`
  and the rest of the actions are skipped (caller logs + moves on).

  ## Failure semantics

  One failing action does not halt the others — the failure is returned
  in the result list as `{:error, type, reason}` but execution continues.
  Unknown action types are returned as `{:error, type, :unknown}`.
  Malformed JSON input returns `{:ok, []}`. `delay` short-circuits
  execution for the remaining actions in that run (they're deferred).
  """

  alias Escalated.Schemas.{DelayedAction, Tag}
  alias Escalated.Services.{AssignmentService, TicketService, WorkflowEngine}
  import Ecto.Query
  require Logger

  @type action :: %{String.t() => any()}
  @type execution_result ::
          {:ok, String.t()}
          | {:error, String.t(), atom()}
          | {:deferred, pos_integer()}

  @doc """
  Execute every action in `actions_json` against `ticket`.

  Returns `{:ok, parsed_actions, results}` where `parsed_actions` is the
  raw decoded list (empty on malformed input) and `results` is a list
  of `{:ok, type}` / `{:error, type, reason}` tuples in the same order
  as the input actions.

  Pass `workflow_id:` in `opts` to enable the `delay` action — otherwise
  `delay` returns `{:error, "delay", :no_workflow_id}` and any actions
  after it are skipped.
  """
  @spec execute(map(), String.t() | nil, keyword()) ::
          {:ok, [action()], [execution_result()]}
  def execute(ticket, actions_json, opts \\ []) do
    actions = parse_actions(actions_json)
    indexed = Enum.with_index(actions)

    {results, _halted?} =
      Enum.reduce(indexed, {[], false}, fn {action, i}, {acc, halted?} ->
        cond do
          halted? ->
            {[{:error, action["type"] || "unknown", :skipped_after_delay} | acc], true}

          (action["type"] || "") == "delay" ->
            remaining = Enum.drop(actions, i + 1)
            result = handle_delay(ticket, action, remaining, opts)
            halt? = match?({:deferred, _}, result) or match?({:error, "delay", _}, result)
            {[result | acc], halt?}

          true ->
            {[dispatch_action(ticket, action) | acc], false}
        end
      end)

    {:ok, actions, Enum.reverse(results)}
  end

  @doc """
  Parse the `workflow.actions` JSON column into a list of action maps.

  Returns `[]` on nil / empty / malformed input.
  """
  @spec parse_actions(String.t() | nil) :: [action()]
  def parse_actions(nil), do: []
  def parse_actions(""), do: []

  def parse_actions(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  def parse_actions(list) when is_list(list), do: list
  def parse_actions(_), do: []

  @doc false
  @spec dispatch_action(map(), action()) :: execution_result()
  def dispatch_action(ticket, %{"type" => type} = action) do
    value = to_string(action["value"] || "")

    try do
      do_dispatch(type, ticket, value)
    rescue
      _ -> {:error, type, :exception}
    end
  end

  def dispatch_action(_ticket, _action), do: {:error, "unknown", :missing_type}

  defp do_dispatch("change_priority", _ticket, ""), do: {:error, "change_priority", :blank_value}

  defp do_dispatch("change_priority", ticket, value) do
    case TicketService.change_priority(ticket, value) do
      {:ok, _} -> {:ok, "change_priority"}
      {:error, _} -> {:error, "change_priority", :update_failed}
    end
  end

  defp do_dispatch("change_status", _ticket, ""), do: {:error, "change_status", :blank_value}

  defp do_dispatch("change_status", ticket, value) do
    case TicketService.transition_status(ticket, value) do
      {:ok, _} -> {:ok, "change_status"}
      {:error, _} -> {:error, "change_status", :update_failed}
    end
  end

  defp do_dispatch("assign_agent", ticket, value) do
    case Integer.parse(value) do
      {agent_id, ""} when agent_id > 0 ->
        case AssignmentService.assign(ticket, agent_id) do
          {:ok, _} -> {:ok, "assign_agent"}
          {:error, _} -> {:error, "assign_agent", :assign_failed}
        end

      _ ->
        {:error, "assign_agent", :invalid_agent_id}
    end
  end

  defp do_dispatch("set_department", ticket, value) do
    with {dept_id, ""} when dept_id > 0 <- Integer.parse(value),
         department <- %Escalated.Schemas.Department{id: dept_id},
         {:ok, _} <- TicketService.change_department(ticket, department) do
      {:ok, "set_department"}
    else
      _ -> {:error, "set_department", :invalid_department}
    end
  end

  defp do_dispatch("add_tag", ticket, value) do
    case resolve_tag_id(value) do
      nil ->
        {:error, "add_tag", :tag_not_found}

      tag_id ->
        case TicketService.add_tags(ticket, [tag_id]) do
          {:ok, _} -> {:ok, "add_tag"}
          {:error, _} -> {:error, "add_tag", :update_failed}
        end
    end
  end

  defp do_dispatch("remove_tag", ticket, value) do
    case resolve_tag_id(value) do
      nil ->
        {:ok, "remove_tag"}

      tag_id ->
        case TicketService.remove_tags(ticket, [tag_id]) do
          {:ok, _} -> {:ok, "remove_tag"}
          {:error, _} -> {:error, "remove_tag", :update_failed}
        end
    end
  end

  defp do_dispatch("add_note", _ticket, ""), do: {:error, "add_note", :blank_value}

  defp do_dispatch("add_note", ticket, body) do
    case TicketService.reply(ticket, %{body: body, is_internal: true, author_id: nil}) do
      {:ok, _reply} -> {:ok, "add_note"}
      {:error, _} -> {:error, "add_note", :insert_failed}
    end
  end

  defp do_dispatch("insert_canned_reply", _ticket, ""),
    do: {:error, "insert_canned_reply", :blank_value}

  defp do_dispatch("insert_canned_reply", ticket, template) do
    body = WorkflowEngine.interpolate(template, ticket_to_map(ticket))

    case TicketService.reply(ticket, %{body: body, is_internal: false, author_id: nil}) do
      {:ok, _reply} -> {:ok, "insert_canned_reply"}
      {:error, _} -> {:error, "insert_canned_reply", :insert_failed}
    end
  end

  # `delay` is handled inline by `execute/3` because it needs the list of
  # remaining actions plus the workflow_id from the caller. Calling
  # `dispatch_action` on a delay directly is a usage error.
  defp do_dispatch("delay", _ticket, _value),
    do: {:error, "delay", :handled_in_execute}

  defp do_dispatch(type, _ticket, _value), do: {:error, type, :unknown}

  # --- Delay handling ---

  @doc false
  @spec handle_delay(map(), action(), [action()], keyword()) :: execution_result()
  def handle_delay(ticket, action, remaining, opts) do
    value = to_string(action["value"] || "")
    workflow_id = Keyword.get(opts, :workflow_id)

    if is_nil(workflow_id) do
      {:error, "delay", :no_workflow_id}
    else
      case Integer.parse(value) do
        {minutes, ""} when minutes > 0 ->
          persist_delayed_actions(workflow_id, ticket, remaining, minutes)

        _ ->
          {:error, "delay", :invalid_minutes}
      end
    end
  end

  defp persist_delayed_actions(workflow_id, ticket, remaining, minutes) do
    execute_at =
      DateTime.utc_now()
      |> DateTime.add(minutes * 60, :second)
      |> DateTime.truncate(:second)

    ticket_id = Map.get(ticket, :id) || Map.get(ticket, "id")
    repo = Escalated.repo()

    # One row per remaining action to match the existing DelayedAction
    # schema shape (`action_data: :map`). The runner sweeps `pending/1`
    # rows and dispatches each through `dispatch_action/2`.
    count =
      remaining
      |> Enum.reduce(0, fn action, acc ->
        attrs = %{
          workflow_id: workflow_id,
          ticket_id: ticket_id,
          action_data: action,
          execute_at: execute_at
        }

        case %DelayedAction{} |> DelayedAction.changeset(attrs) |> repo.insert() do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    {:deferred, count}
  end

  @doc """
  Dispatch every pending `DelayedAction` whose `execute_at` has elapsed.

  For each row, re-loads the ticket, runs `dispatch_action/2` on the
  stored `action_data`, and stamps `executed=true`. Failures are
  logged but do not stop the sweep.

  Intended to be called periodically from host-app cron via
  `mix escalated.run_due_delayed_actions`.

  Returns `{processed, failed}` tuple.
  """
  @spec run_due_delayed_actions() :: {non_neg_integer(), non_neg_integer()}
  def run_due_delayed_actions do
    repo = Escalated.repo()

    DelayedAction
    |> DelayedAction.pending()
    |> repo.all()
    |> Enum.reduce({0, 0}, fn delayed, {ok_count, err_count} ->
      case run_one_delayed(delayed) do
        :ok -> {ok_count + 1, err_count}
        :error -> {ok_count, err_count + 1}
      end
    end)
  end

  defp run_one_delayed(%DelayedAction{} = delayed) do
    repo = Escalated.repo()

    with ticket when not is_nil(ticket) <-
           repo.get(Escalated.Schemas.Ticket, delayed.ticket_id),
         {:ok, _type} <- dispatch_action(ticket, delayed.action_data) do
      delayed
      |> DelayedAction.changeset(%{executed: true})
      |> repo.update()

      :ok
    else
      nil ->
        Logger.warning(
          "[WorkflowExecutor] delayed_action #{delayed.id}: ticket ##{delayed.ticket_id} not found"
        )

        delayed
        |> DelayedAction.changeset(%{executed: true})
        |> repo.update()

        :error

      {:error, type, reason} ->
        Logger.warning(
          "[WorkflowExecutor] delayed_action #{delayed.id}: #{type} failed (#{inspect(reason)})"
        )

        delayed
        |> DelayedAction.changeset(%{executed: true})
        |> repo.update()

        :error

      other ->
        Logger.warning(
          "[WorkflowExecutor] delayed_action #{delayed.id}: unexpected result #{inspect(other)}"
        )

        :error
    end
  end

  @doc false
  @spec resolve_tag_id(String.t()) :: integer() | nil
  def resolve_tag_id(""), do: nil

  def resolve_tag_id(value) do
    repo = Escalated.repo()

    by_name =
      from(t in Tag, where: t.name == ^value, select: t.id, limit: 1)
      |> repo.one()

    cond do
      not is_nil(by_name) ->
        by_name

      match?({_, ""}, Integer.parse(value)) ->
        {as_id, ""} = Integer.parse(value)

        from(t in Tag, where: t.id == ^as_id, select: t.id, limit: 1)
        |> repo.one()

      true ->
        nil
    end
  end

  @doc false
  @spec ticket_to_map(map()) :: map()
  def ticket_to_map(ticket) do
    %{
      reference: Map.get(ticket, :reference, ""),
      subject: Map.get(ticket, :subject, ""),
      status: Map.get(ticket, :status, ""),
      priority: Map.get(ticket, :priority, "")
    }
  end
end
