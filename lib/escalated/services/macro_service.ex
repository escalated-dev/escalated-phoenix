defmodule Escalated.Services.MacroService do
  @moduledoc """
  Agent-applied, manual one-click action bundles.

  Distinct from Workflow (admin event-driven) and Automation (admin
  time-based). See escalated-developer-context/domain-model/
  workflows-automations-macros.md.

  ## Usage

  Agent picks a macro from a dropdown on a specific ticket, then
  triggers `apply/4` which runs each action in the bundle in order
  against that ticket. Per-action failures are caught and logged so
  one bad action does not abort the rest.
  """

  require Logger

  alias Escalated.Schemas.{Macro, Ticket, Reply, Tag}

  @doc """
  Macros visible to an agent: shared macros plus macros they created.
  """
  @spec list_for_agent(module(), integer()) :: [Macro.t()] | [%Macro{}]
  def list_for_agent(repo, agent_id) when is_atom(repo) and is_integer(agent_id) do
    Macro
    |> Macro.for_agent(agent_id)
    |> repo.all()
  end

  @spec find_by_id(module(), integer()) :: %Macro{} | nil
  def find_by_id(repo, id) do
    repo.get(Macro, id)
  end

  @spec create(module(), map()) :: {:ok, %Macro{}} | {:error, Ecto.Changeset.t()}
  def create(repo, attrs) do
    %Macro{}
    |> Macro.changeset(attrs)
    |> repo.insert()
  end

  @spec update(module(), %Macro{}, map()) :: {:ok, %Macro{}} | {:error, Ecto.Changeset.t()}
  def update(repo, %Macro{} = macro, attrs) do
    macro
    |> Macro.changeset(attrs)
    |> repo.update()
  end

  @spec delete(module(), %Macro{}) :: {:ok, %Macro{}} | {:error, Ecto.Changeset.t()}
  def delete(repo, %Macro{} = macro) do
    repo.delete(macro)
  end

  @doc """
  Apply a macro to a ticket. Each action runs in order; per-action
  failure is rescued and logged so one bad action does not abort the
  rest of the bundle.
  """
  @spec apply(module(), %Macro{}, %Ticket{}, integer()) :: %Ticket{}
  def apply(repo, %Macro{actions: actions, id: macro_id}, %Ticket{} = ticket, agent_id) do
    Enum.reduce(actions || [], ticket, fn action, t ->
      try do
        run_action(action, t, agent_id, macro_id, repo)
      rescue
        e ->
          Logger.warning(
            "Macro ##{macro_id} action #{inspect(action["type"])} on ticket ##{t.id} (agent #{agent_id}) failed: #{inspect(e)}"
          )

          t
      end
    end)
  end

  defp run_action(%{"type" => type, "value" => v}, ticket, _agent_id, _mid, repo)
       when type in ["change_status", "set_status"] do
    {:ok, t} =
      ticket
      |> Ticket.changeset(%{status: to_string(v)})
      |> repo.update()

    t
  end

  defp run_action(%{"type" => type, "value" => v}, ticket, _agent_id, _mid, repo)
       when type in ["change_priority", "set_priority"] do
    {:ok, t} =
      ticket
      |> Ticket.changeset(%{priority: to_string(v)})
      |> repo.update()

    t
  end

  defp run_action(%{"type" => "assign", "value" => v}, ticket, _agent_id, _mid, repo) do
    {:ok, t} =
      ticket
      |> Ticket.changeset(%{assigned_to: v})
      |> repo.update()

    t
  end

  defp run_action(%{"type" => "add_tag", "value" => v}, ticket, _agent_id, _mid, repo) do
    case repo.get_by(Tag, name: to_string(v)) do
      nil ->
        ticket

      %Tag{} = tag ->
        join_table =
          "#{Application.get_env(:escalated, :table_prefix, "escalated_")}ticket_tag"

        repo.insert_all(
          join_table,
          [%{ticket_id: ticket.id, tag_id: tag.id}],
          on_conflict: :nothing
        )

        ticket
    end
  end

  defp run_action(%{"type" => "add_reply", "value" => v}, ticket, agent_id, _mid, repo) do
    create_reply(repo, ticket, agent_id, to_string(v), false)
    ticket
  end

  defp run_action(%{"type" => "add_note", "value" => v}, ticket, agent_id, _mid, repo) do
    create_reply(repo, ticket, agent_id, to_string(v), true)
    ticket
  end

  defp run_action(%{"type" => "insert_canned_reply", "value" => v}, ticket, agent_id, _mid, repo) do
    # Frontend resolves the canned response template before POSTing;
    # stored value here is the resolved text body.
    create_reply(repo, ticket, agent_id, to_string(v), false)
    ticket
  end

  defp run_action(_unknown, ticket, _agent_id, _mid, _repo), do: ticket

  defp create_reply(repo, ticket, author_id, body, is_internal) do
    %Reply{}
    |> Reply.changeset(%{
      ticket_id: ticket.id,
      author_id: author_id,
      body: body,
      is_internal_note: is_internal
    })
    |> repo.insert()
  end
end
