defmodule Escalated.Services.TicketStatusService do
  @moduledoc """
  Custom ticket statuses (`Escalated.Schemas.TicketStatus`): resolving a
  status input to a built-in status or a custom one, slugs, system rows and
  the `custom_status` / `status_category` fields staff ticket payloads carry.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{Ticket, TicketStatus}

  @doc "Every status of the current tenant, by category then position."
  def list do
    order = TicketStatus.categories()

    from(s in TicketStatus, order_by: [asc: s.position, asc: s.id])
    |> repo().all()
    |> Enum.sort_by(fn s -> Enum.find_index(order, &(&1 == s.category)) || length(order) end)
  end

  @doc """
  Inserts the system rows the current tenant is missing (one per built-in
  status). The migration seeds them for the single-tenant namespace; a
  merchant namespace gets them here. Lifecycle code never needs them.
  """
  def ensure_system_statuses do
    existing = from(s in TicketStatus, select: s.slug) |> repo().all() |> MapSet.new()

    TicketStatus.system_statuses()
    |> Enum.with_index()
    |> Enum.reject(fn {{slug, _, _, _}, _} -> MapSet.member?(existing, slug) end)
    |> Enum.each(fn {definition, position} ->
      # A concurrent request may insert the same row; the unique index keeps one.
      _ = definition |> TicketStatus.system_changeset(position) |> repo().insert()
    end)

    :ok
  end

  @doc """
  What a status input means: `{:builtin, status}` for a built-in status,
  `{:custom, %TicketStatus{}}` for a custom status's slug, else `:unknown`.
  """
  def resolve(%TicketStatus{is_system: false} = status), do: {:custom, status}
  def resolve(%TicketStatus{slug: slug}), do: {:builtin, slug}

  def resolve(value) when is_binary(value) do
    cond do
      value in Ticket.statuses() -> {:builtin, value}
      status = find_custom(value) -> {:custom, status}
      true -> :unknown
    end
  end

  def resolve(value) when is_atom(value) and not is_nil(value), do: resolve(Atom.to_string(value))
  def resolve(_), do: :unknown

  @doc "Whether `ticket` already has the status `value` names."
  def current?(%Ticket{} = ticket, value) do
    case resolve(value) do
      {:builtin, status} -> ticket.status == status and is_nil(ticket.ticket_status_id)
      {:custom, status} -> ticket.ticket_status_id == status.id
      :unknown -> false
    end
  end

  @doc "The custom (non-system) status with `slug`, or nil."
  def find_custom(slug) when is_binary(slug) and slug != "" do
    repo().one(from(s in TicketStatus, where: s.slug == ^slug and s.is_system == false))
  end

  def find_custom(_), do: nil

  @doc "A slug for `label`, unique in the current tenant: `_2`, `_3`... when taken."
  def unique_slug(label) do
    base =
      label
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> then(&if(&1 == "", do: "status", else: &1))

    taken =
      from(s in TicketStatus,
        where: like(s.slug, ^(base <> "%")),
        select: s.slug
      )
      |> repo().all()
      |> MapSet.new()

    taken = MapSet.union(taken, MapSet.new(Ticket.statuses()))

    if MapSet.member?(taken, base) do
      Stream.iterate(2, &(&1 + 1))
      |> Enum.find_value(fn n ->
        candidate = "#{base}_#{n}"
        if MapSet.member?(taken, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  @doc "A status row as the admin pages read it."
  def status_json(%TicketStatus{} = s) do
    %{
      id: s.id,
      label: s.label,
      slug: s.slug,
      category: s.category,
      color: s.color,
      description: s.description,
      position: s.position,
      is_default: s.is_default,
      is_system: s.is_system,
      created_at: iso(s.inserted_at),
      updated_at: iso(s.updated_at)
    }
  end

  @doc """
  The staff payload fields for `ticket`: `custom_status` (`{id, label, slug,
  color, category}` or nil) and `status_category`. The ticket's
  `ticket_status` is loaded when it is not.
  """
  def ticket_fields(%Ticket{} = ticket) do
    custom =
      case ticket.ticket_status_id && load(ticket) do
        %TicketStatus{} = s ->
          %{id: s.id, label: s.label, slug: s.slug, color: s.color, category: s.category}

        _ ->
          nil
      end

    %{
      custom_status: custom,
      status_category: if(custom, do: custom.category, else: builtin_category(ticket.status))
    }
  end

  defp builtin_category(nil), do: "open"
  defp builtin_category(status), do: TicketStatus.builtin_category(status)

  defp load(%Ticket{ticket_status: %TicketStatus{id: id} = s, ticket_status_id: id}), do: s
  defp load(%Ticket{ticket_status_id: id}), do: repo().get(TicketStatus, id)

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"

  defp repo, do: Escalated.repo()
end
