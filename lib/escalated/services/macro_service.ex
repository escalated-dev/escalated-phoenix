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

  alias Escalated.Schemas.{Macro, Tag, Ticket}
  alias Escalated.Services.{RuleActions, TicketService}

  @doc """
  Macros visible to an agent: shared macros plus macros they created.
  """
  @spec list_for_agent(module(), integer()) :: [Macro.t()]
  def list_for_agent(repo, agent_id) when is_atom(repo) and is_integer(agent_id) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    Macro
    |> Macro.for_agent(agent_id)
    |> repo.all()
  end

  @spec find_by_id(module(), integer()) :: Macro.t() | nil
  def find_by_id(repo, id) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    repo.get(Macro, id)
  end

  @spec create(module(), map()) :: {:ok, Macro.t()} | {:error, Ecto.Changeset.t()}
  def create(repo, attrs) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    %Macro{}
    |> Macro.changeset(attrs)
    |> repo.insert()
  end

  @spec update(module(), Macro.t(), map()) :: {:ok, Macro.t()} | {:error, Ecto.Changeset.t()}
  def update(repo, %Macro{} = macro, attrs) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    macro
    |> Macro.changeset(attrs)
    |> repo.update()
  end

  @spec delete(module(), Macro.t()) :: {:ok, Macro.t()} | {:error, Ecto.Changeset.t()}
  def delete(repo, %Macro{} = macro) do
    repo = Escalated.Tenancy.scoped_repo(repo)

    repo.delete(macro)
  end

  @doc """
  Apply a macro to a ticket. Each action runs in order; per-action
  failure is rescued and logged so one bad action does not abort the
  rest of the bundle.
  """
  @spec apply(module(), Macro.t(), Ticket.t(), integer()) :: Ticket.t()
  def apply(repo, %Macro{actions: actions, id: macro_id} = macro, %Ticket{} = ticket, agent_id) do
    repo = Escalated.Tenancy.scoped_repo(repo)
    Escalated.Tenancy.assert_record!(macro)
    Escalated.Tenancy.assert_record!(ticket)

    Enum.reduce(actions || [], ticket, fn action, t ->
      try do
        case run_action(action, t, agent_id, macro_id, repo) do
          {:ok, %Ticket{} = updated} ->
            updated

          {:error, reason} ->
            Logger.warning(
              "Macro ##{macro_id} action #{inspect(action["type"])} on ticket ##{t.id} (agent #{agent_id}) failed: #{inspect(reason)}"
            )

            t

          _ ->
            t
        end
      rescue
        e ->
          Logger.warning(
            "Macro ##{macro_id} action #{inspect(action["type"])} on ticket ##{t.id} (agent #{agent_id}) failed: #{inspect(e)}"
          )

          t
      end
    end)
  end

  # Field changes, replies and notes go through TicketService /
  # AssignmentService (as Laravel's MacroService does), so status, priority
  # and assignment events, activity rows, workflows, mentions and assignment
  # checks all run, attributed to the agent who applied the macro.
  defp run_action(%{"type" => type, "value" => v}, ticket, agent_id, _mid, _repo)
       when type in ["change_status", "set_status"],
       do: RuleActions.change_status(ticket, v, actor_id: agent_id)

  defp run_action(%{"type" => type, "value" => v}, ticket, agent_id, _mid, _repo)
       when type in ["change_priority", "set_priority"],
       do: RuleActions.change_priority(ticket, v, actor_id: agent_id)

  defp run_action(%{"type" => "assign", "value" => v}, ticket, agent_id, _mid, _repo),
    do: RuleActions.assign(ticket, v, actor_id: agent_id)

  defp run_action(%{"type" => "add_tag", "value" => v}, ticket, _agent_id, _mid, repo) do
    case repo.get_by(Tag, name: to_string(v)) do
      nil ->
        {:ok, ticket}

      %Tag{} = tag ->
        join_table =
          "#{Application.get_env(:escalated, :table_prefix, "escalated_")}ticket_tags"

        repo.insert_all(
          join_table,
          [%{ticket_id: ticket.id, tag_id: tag.id}],
          on_conflict: :nothing
        )

        {:ok, ticket}
    end
  end

  defp run_action(%{"type" => "add_reply", "value" => v}, ticket, agent_id, _mid, _repo),
    do: create_reply(ticket, agent_id, to_string(v), false)

  defp run_action(%{"type" => "add_note", "value" => v}, ticket, agent_id, _mid, _repo),
    do: create_reply(ticket, agent_id, to_string(v), true)

  defp run_action(%{"type" => "insert_canned_reply", "value" => v}, ticket, agent_id, _mid, _repo) do
    # Frontend resolves the canned response template before POSTing;
    # stored value here is the resolved text body.
    create_reply(ticket, agent_id, to_string(v), false)
  end

  defp run_action(_unknown, ticket, _agent_id, _mid, _repo), do: {:ok, ticket}

  # `is_internal` is the flag Reply casts; a note must never become a public
  # reply the requester can see.
  defp create_reply(ticket, author_id, body, is_internal) do
    with {:ok, _reply} <-
           TicketService.reply(ticket, %{
             author_id: author_id,
             body: body,
             is_internal: is_internal
           }) do
      {:ok, Escalated.repo().get(Ticket, ticket.id) || ticket}
    end
  end
end
