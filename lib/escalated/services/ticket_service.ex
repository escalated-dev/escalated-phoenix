defmodule Escalated.Services.TicketService do
  @moduledoc """
  Core service for ticket operations: create, reply, status transitions, etc.
  """

  alias Escalated.Schemas.{Ticket, Reply, TicketActivity}
  import Ecto.Query

  @doc """
  Creates a new ticket.
  """
  def create(attrs) do
    repo = Escalated.repo()

    %Ticket{}
    |> Ticket.changeset(attrs)
    |> repo.insert()
    |> case do
      {:ok, ticket} ->
        log_activity(ticket, "created", nil, %{})
        maybe_attach_sla(ticket)
        {:ok, ticket}

      error ->
        error
    end
  end

  @doc """
  Adds a reply (or internal note) to a ticket.
  """
  def reply(ticket, attrs) do
    repo = Escalated.repo()

    reply_attrs =
      attrs
      |> Map.put(:ticket_id, ticket.id)

    %Reply{}
    |> Reply.changeset(reply_attrs)
    |> repo.insert()
    |> case do
      {:ok, reply} ->
        action = if reply.is_internal, do: "note_added", else: "reply_added"
        log_activity(ticket, action, reply.author_id, %{reply_id: reply.id})

        # Track first response
        if !reply.is_internal && is_nil(ticket.first_response_at) && reply.author_id != ticket.requester_id do
          ticket
          |> Ticket.changeset(%{first_response_at: DateTime.utc_now()})
          |> repo.update()
        end

        {:ok, reply}

      error ->
        error
    end
  end

  @doc """
  Transitions a ticket to a new status.
  """
  def transition_status(ticket, new_status, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)
    note = Keyword.get(opts, :note)

    updates = %{status: new_status}

    updates =
      case new_status do
        "resolved" -> Map.put(updates, :resolved_at, DateTime.utc_now())
        "closed" -> Map.put(updates, :closed_at, DateTime.utc_now())
        "reopened" -> Map.merge(updates, %{resolved_at: nil, closed_at: nil})
        _ -> updates
      end

    ticket
    |> Ticket.changeset(updates)
    |> repo.update()
    |> case do
      {:ok, updated} ->
        details = %{from: ticket.status, to: new_status}
        details = if note, do: Map.put(details, :note, note), else: details
        log_activity(updated, "status_changed", actor_id, details)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Changes a ticket's priority.
  """
  def change_priority(ticket, new_priority, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    ticket
    |> Ticket.changeset(%{priority: new_priority})
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "priority_changed", actor_id, %{
          from: ticket.priority,
          to: new_priority
        })

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Changes a ticket's department.
  """
  def change_department(ticket, department, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    ticket
    |> Ticket.changeset(%{department_id: department.id})
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "department_changed", actor_id, %{
          from_id: ticket.department_id,
          to_id: department.id,
          to_name: department.name
        })

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Adds tags to a ticket.
  """
  def add_tags(ticket, tag_ids, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)
    tags = repo.all(from(t in Escalated.Schemas.Tag, where: t.id in ^tag_ids))

    ticket = repo.preload(ticket, :tags)
    existing_ids = Enum.map(ticket.tags, & &1.id)
    new_tags = Enum.reject(tags, fn t -> t.id in existing_ids end)
    all_tags = ticket.tags ++ new_tags

    ticket
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, all_tags)
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "tags_added", actor_id, %{tag_ids: Enum.map(new_tags, & &1.id)})
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Removes tags from a ticket.
  """
  def remove_tags(ticket, tag_ids, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    ticket = repo.preload(ticket, :tags)
    remaining = Enum.reject(ticket.tags, fn t -> t.id in tag_ids end)

    ticket
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:tags, remaining)
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "tags_removed", actor_id, %{tag_ids: tag_ids})
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Lists tickets with optional filters.
  """
  def list(filters \\ %{}) do
    repo = Escalated.repo()

    Ticket
    |> maybe_filter(:status, filters)
    |> maybe_filter(:priority, filters)
    |> maybe_filter(:department_id, filters)
    |> maybe_filter(:assigned_to, filters)
    |> maybe_search(filters)
    |> maybe_unassigned(filters)
    |> maybe_breached(filters)
    |> Ticket.recent()
    |> repo.all()
  end

  @doc """
  Finds a ticket by reference or ID.
  """
  def find(reference) when is_binary(reference) do
    repo = Escalated.repo()
    repo.get_by(Ticket, reference: reference) || repo.get(Ticket, reference)
  end

  def find(id) when is_integer(id) do
    Escalated.repo().get(Ticket, id)
  end

  # Private helpers

  defp log_activity(ticket, action, causer_id, details) do
    repo = Escalated.repo()

    %TicketActivity{}
    |> TicketActivity.changeset(%{
      ticket_id: ticket.id,
      action: action,
      causer_id: causer_id,
      details: details,
      description: "#{action}: #{inspect(details)}"
    })
    |> repo.insert()
  end

  defp maybe_attach_sla(ticket) do
    config = Escalated.configuration()

    if Escalated.Config.sla_enabled?(config) do
      Escalated.Services.SlaService.attach_policy(ticket)
    end
  end

  defp maybe_filter(query, key, filters) do
    case Map.get(filters, key) do
      nil -> query
      value -> from(t in query, where: field(t, ^key) == ^value)
    end
  end

  defp maybe_search(query, %{search: term}) when is_binary(term) and term != "" do
    Ticket.search(query, term)
  end

  defp maybe_search(query, _), do: query

  defp maybe_unassigned(query, %{unassigned: true}), do: Ticket.unassigned(query)
  defp maybe_unassigned(query, _), do: query

  defp maybe_breached(query, %{sla_breached: true}), do: Ticket.breached_sla(query)
  defp maybe_breached(query, _), do: query
end
