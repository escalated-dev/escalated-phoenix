defmodule Escalated.Services.WorkflowExecutor do
  @moduledoc """
  Performs the side-effects dictated by a matched `Workflow`.

  Distinct from `Escalated.Services.WorkflowEngine`, which only evaluates
  conditions. This module parses the JSON action array stored on
  `workflow.actions` and dispatches each entry against `TicketService` /
  `AssignmentService` / `Escalated.repo/0`.

  ## Action catalog

  `change_priority`, `change_status`, `assign_agent`, `set_department`,
  `add_tag`, `remove_tag`, `add_note`, `insert_canned_reply`.

  Mirrors the NestJS reference impl in
  `escalated-nestjs/src/services/workflow-executor.service.ts`.

  ## Failure semantics

  One failing action does not halt the others — the failure is returned
  in the result list as `{:error, type, reason}` but execution continues.
  Unknown action types are returned as `{:error, type, :unknown}`.
  Malformed JSON input returns `{:ok, []}`.
  """

  alias Escalated.Services.{AssignmentService, TicketService, WorkflowEngine}
  alias Escalated.Schemas.{Reply, Tag}
  import Ecto.Query

  @type action :: %{String.t() => any()}
  @type execution_result :: {:ok, String.t()} | {:error, String.t(), atom()}

  @doc """
  Execute every action in `actions_json` against `ticket`.

  Returns `{:ok, parsed_actions, results}` where `parsed_actions` is the
  raw decoded list (empty on malformed input) and `results` is a list
  of `{:ok, type}` / `{:error, type, reason}` tuples in the same order
  as the input actions.
  """
  @spec execute(map(), String.t() | nil) :: {:ok, [action()], [execution_result()]}
  def execute(ticket, actions_json) do
    actions = parse_actions(actions_json)
    results = Enum.map(actions, &dispatch_action(ticket, &1))
    {:ok, actions, results}
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

  defp do_dispatch(type, _ticket, _value), do: {:error, type, :unknown}

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
