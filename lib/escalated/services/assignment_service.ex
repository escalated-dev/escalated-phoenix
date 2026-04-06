defmodule Escalated.Services.AssignmentService do
  @moduledoc """
  Service for ticket assignment operations: assign, unassign, round-robin, bulk.
  """

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.TicketService
  import Ecto.Query

  @doc """
  Assigns a ticket to an agent.
  """
  def assign(ticket, agent_id, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    ticket
    |> Ticket.changeset(%{assigned_to: agent_id})
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "assigned", actor_id, %{agent_id: agent_id})
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Removes the assignee from a ticket.
  """
  def unassign(ticket, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)
    old_agent_id = ticket.assigned_to

    ticket
    |> Ticket.changeset(%{assigned_to: nil})
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "unassigned", actor_id, %{previous_agent_id: old_agent_id})
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Auto-assigns a ticket using round-robin within the ticket's department.
  Returns `{:ok, ticket}` with the assigned agent, or `{:ok, nil}` if no agents available.
  """
  def auto_assign(ticket) do
    case ticket.department_id do
      nil ->
        {:ok, nil}

      dept_id ->
        case next_available_agent(dept_id) do
          nil -> {:ok, nil}
          agent_id -> assign(ticket, agent_id)
        end
    end
  end

  @doc """
  Reassigns a ticket from one agent to another, emitting a reassignment event.
  """
  def reassign(ticket, new_agent_id, opts \\ []) do
    old_agent_id = ticket.assigned_to
    actor_id = Keyword.get(opts, :actor_id)

    with {:ok, updated} <- assign(ticket, new_agent_id, opts) do
      log_activity(updated, "reassigned", actor_id, %{
        from_agent_id: old_agent_id,
        to_agent_id: new_agent_id
      })

      {:ok, updated}
    end
  end

  @doc """
  Assigns multiple tickets to a single agent.
  """
  def bulk_assign(ticket_ids, agent_id, opts \\ []) do
    repo = Escalated.repo()
    tickets = repo.all(from(t in Ticket, where: t.id in ^ticket_ids))

    results =
      Enum.map(tickets, fn ticket ->
        assign(ticket, agent_id, opts)
      end)

    {:ok, results}
  end

  @doc """
  Unassigns multiple tickets.
  """
  def bulk_unassign(ticket_ids, opts \\ []) do
    repo = Escalated.repo()
    tickets = repo.all(from(t in Ticket, where: t.id in ^ticket_ids))

    results =
      Enum.map(tickets, fn ticket ->
        unassign(ticket, opts)
      end)

    {:ok, results}
  end

  # Private

  defp next_available_agent(department_id) do
    repo = Escalated.repo()

    # Find agents in this department via agent_profiles or department_agents join table.
    # For now, use a simple round-robin: agent with fewest open tickets in this department.
    agent_profiles =
      repo.all(
        from(ap in Escalated.Schemas.AgentProfile,
          where: ap.is_active == true,
          select: ap.user_id
        )
      )

    case agent_profiles do
      [] ->
        nil

      agent_ids ->
        # Count open tickets per agent in this department
        loads =
          Enum.map(agent_ids, fn agent_id ->
            count =
              repo.aggregate(
                from(t in Ticket,
                  where:
                    t.assigned_to == ^agent_id and
                      t.department_id == ^department_id and
                      t.status in ^~w(open in_progress waiting_on_customer waiting_on_agent escalated reopened)
                ),
                :count
              )

            {agent_id, count}
          end)

        {agent_id, _} = Enum.min_by(loads, fn {_, count} -> count end)
        agent_id
    end
  end

  defp log_activity(ticket, action, causer_id, details) do
    repo = Escalated.repo()

    %Escalated.Schemas.TicketActivity{}
    |> Escalated.Schemas.TicketActivity.changeset(%{
      ticket_id: ticket.id,
      action: action,
      causer_id: causer_id,
      details: details
    })
    |> repo.insert()
  end
end
