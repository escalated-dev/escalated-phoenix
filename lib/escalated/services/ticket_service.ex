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
  Snoozes a ticket until a given datetime.

  Transitions the ticket to "snoozed" status, records the previous status,
  and stores who snoozed it and until when.

  ## Parameters

    * `ticket` - the ticket to snooze
    * `until` - a `DateTime` for when the ticket should wake
    * `opts` - keyword list with `:actor_id`

  ## Returns

    * `{:ok, ticket}` on success
    * `{:error, changeset}` on failure
  """
  def snooze_ticket(ticket, until, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)

    ticket
    |> Ticket.changeset(%{
      status: "snoozed",
      status_before_snooze: ticket.status,
      snoozed_until: until,
      snoozed_by: actor_id
    })
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "snoozed", actor_id, %{
          until: DateTime.to_iso8601(until),
          previous_status: ticket.status
        })

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Splits a ticket by creating a new ticket from a specific reply.

  Copies metadata from the original ticket, links both tickets via metadata,
  and logs activity on both tickets.

  ## Parameters

    * `ticket` - the original ticket struct
    * `reply` - the reply to use as the basis for the new ticket
    * `opts` - keyword list of options:
      * `:actor_id` - ID of the user performing the split
      * `:subject` - optional subject override for the new ticket

  ## Returns

    * `{:ok, new_ticket}` on success
    * `{:error, changeset}` on failure
  """
  def split_ticket(ticket, reply, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)
    subject = Keyword.get(opts, :subject, "Split from #{ticket.reference}: #{ticket.subject}")

    new_ticket_attrs = %{
      subject: subject,
      description: reply.body,
      status: "open",
      priority: ticket.priority,
      ticket_type: ticket.ticket_type,
      department_id: ticket.department_id,
      requester_id: ticket.requester_id,
      requester_type: ticket.requester_type,
      guest_name: ticket.guest_name,
      guest_email: ticket.guest_email,
      metadata: Map.merge(ticket.metadata || %{}, %{"split_from_ticket_id" => ticket.id, "split_from_reply_id" => reply.id})
    }

    %Ticket{}
    |> Ticket.changeset(new_ticket_attrs)
    |> repo.insert()
    |> case do
      {:ok, new_ticket} ->
        # Update original ticket metadata to link to the new ticket
        original_splits = Map.get(ticket.metadata || %{}, "split_ticket_ids", [])

        ticket
        |> Ticket.changeset(%{
          metadata: Map.put(ticket.metadata || %{}, "split_ticket_ids", original_splits ++ [new_ticket.id])
        })
        |> repo.update()

        # Log activity on both tickets
        log_activity(ticket, "ticket_split", actor_id, %{
          new_ticket_id: new_ticket.id,
          new_ticket_reference: new_ticket.reference,
          reply_id: reply.id
        })

        log_activity(new_ticket, "created_from_split", actor_id, %{
          original_ticket_id: ticket.id,
          original_ticket_reference: ticket.reference,
          reply_id: reply.id
        })

        {:ok, new_ticket}

      error ->
        error
    end

    @doc """
  Unsnoozes a ticket, restoring its previous status.

  Clears the snooze fields and transitions back to the status the ticket
  had before it was snoozed (defaults to "open").

  ## Parameters

    * `ticket` - the snoozed ticket
    * `opts` - keyword list with `:actor_id`

  ## Returns

    * `{:ok, ticket}` on success
    * `{:error, changeset}` on failure
  """
  def unsnooze_ticket(ticket, opts \\ []) do
    repo = Escalated.repo()
    actor_id = Keyword.get(opts, :actor_id)
    restore_status = ticket.status_before_snooze || "open"

    ticket
    |> Ticket.changeset(%{
      status: restore_status,
      status_before_snooze: nil,
      snoozed_until: nil,
      snoozed_by: nil
    })
    |> repo.update()
    |> case do
      {:ok, updated} ->
        log_activity(updated, "unsnoozed", actor_id, %{
          restored_status: restore_status
        })

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Wakes all tickets whose snooze period has elapsed.

  Returns a list of `{:ok, ticket}` tuples for each ticket that was woken.
  """
  def wake_snoozed_tickets do
    repo = Escalated.repo()
    tickets = repo.all(Ticket.wake_due())

    Enum.map(tickets, fn ticket ->
      unsnooze_ticket(ticket)
    end)
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
