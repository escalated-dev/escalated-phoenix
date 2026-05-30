defmodule Escalated.Services.TicketSubjectService do
  @moduledoc """
  Attach, detach, sync, and list ticket subjects (host entities a ticket is about).
  """

  alias Escalated.Schemas.{Ticket, TicketSubject}
  alias Escalated.TicketSubjects
  import Ecto.Query

  @doc """
  Lists subject links for a ticket, ordered by position.
  """
  def list(%Ticket{id: ticket_id}) do
    Escalated.repo().all(TicketSubject.for_ticket(ticket_id) |> TicketSubject.ordered())
  end

  @doc """
  Attaches a subject to a ticket (idempotent on ticket + type + id).

  ## Options

    * `:role` — optional label (e.g. `"project"`)
    * `:position` — explicit ordering; defaults to max(position) + 1
    * `:enforce_allowlist` — when true (default), reject types outside the configured
      allowlist when the allowlist is non-empty. Set false for programmatic use when
      the allowlist is empty or you intentionally bypass it.

  Raises `ArgumentError` when the type is not permitted.
  """
  def attach_subject(ticket, type, id, opts \\ [])
      when is_binary(type) and is_binary(id) do
    enforce? = Keyword.get(opts, :enforce_allowlist, true)

    if enforce? and not TicketSubjects.type_allowed?(type) do
      raise ArgumentError,
            "Subject type [#{type}] is not an allowed ticket subject."
    end

    repo = Escalated.repo()
    role = Keyword.get(opts, :role)
    position = Keyword.get(opts, :position) || next_position(repo, ticket.id)
    subject_id = to_string(id)

    attrs = %{
      ticket_id: ticket.id,
      subject_type: type,
      subject_id: subject_id,
      role: role,
      position: position
    }

    case repo.get_by(TicketSubject,
           ticket_id: ticket.id,
           subject_type: type,
           subject_id: subject_id
         ) do
      nil ->
        %TicketSubject{}
        |> TicketSubject.changeset(attrs)
        |> repo.insert()

      link ->
        link
        |> TicketSubject.changeset(Map.take(attrs, [:role, :position]))
        |> repo.update()
    end
  end

  @doc """
  Detaches a subject from a ticket. Returns `{:ok, count}` with 0 or 1.
  """
  def detach_subject(ticket, type, id) when is_binary(type) do
    repo = Escalated.repo()
    subject_id = to_string(id)

    {count, _} =
      repo.delete_all(
        from(s in TicketSubject,
          where:
            s.ticket_id == ^ticket.id and s.subject_type == ^type and
              s.subject_id == ^subject_id
        )
      )

    {:ok, count}
  end

  @doc """
  Replaces all subjects on a ticket.

  `entries` is an enumerable of:

    * `{type, id}` or `{type, id, role}`
    * or a map with `:type`/`:id`/optional `:role` (string keys accepted)

  Order is preserved via `position` starting at 0.
  """
  def sync_subjects(ticket, entries) when is_list(entries) or is_map(entries) do
    repo = Escalated.repo()

    repo.transaction(fn ->
      repo.delete_all(from(s in TicketSubject, where: s.ticket_id == ^ticket.id))

      entries
      |> Enum.with_index()
      |> Enum.each(fn {entry, position} ->
        {type, id, role} = normalize_entry(entry)

        case attach_subject(ticket, type, id, role: role, position: position) do
          {:ok, _} -> :ok
          {:error, changeset} -> repo.rollback(changeset)
        end
      end)

      list(ticket)
    end)
    |> case do
      {:ok, links} -> {:ok, links}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_subjects(ticket, entries) do
    sync_subjects(ticket, Enum.to_list(entries))
  end

  defp normalize_entry({type, id}) when is_binary(type), do: {type, to_string(id), nil}

  defp normalize_entry({type, id, role}) when is_binary(type),
    do: {type, to_string(id), role}

  defp normalize_entry(%{} = map) do
    type = Map.get(map, :type) || Map.get(map, "type")
    id = Map.get(map, :id) || Map.get(map, "id")
    role = Map.get(map, :role) || Map.get(map, "role")
    {type, to_string(id), role}
  end

  defp next_position(repo, ticket_id) do
    max =
      repo.one(
        from(s in TicketSubject,
          where: s.ticket_id == ^ticket_id,
          select: max(s.position)
        )
      )

    (max || -1) + 1
  end
end
