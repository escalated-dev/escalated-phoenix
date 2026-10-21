defmodule Escalated.Controllers.BulkActionController do
  @moduledoc """
  Bulk ticket actions from the shared `BulkActionBar`, as escalated-laravel's
  `BulkActionController`. Mounted for admins (`escalated.admin.tickets.bulk`)
  and agents (`escalated.agent.tickets.bulk`) at `POST .../tickets/bulk`.

  The body is `{ticket_ids: [id, ...], action, value}`: 1 to 50 ids, and an
  action of `status`, `priority`, `assign`, `tags` (a list of tag ids),
  `department` or `delete` (admins only; no value). Each ticket goes through
  the same service an agent's single change does, so events, workflows and
  notification emails run per ticket. A ticket that cannot be changed is
  skipped. Redirects back with a flash naming how many were updated.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Schemas.{Department, Ticket}
  alias Escalated.Services.{AssignmentService, TicketService}

  require Logger

  @actions ~w(status priority assign tags department delete)
  @max_tickets 50

  def bulk(conn, params) do
    user = conn.assigns[:current_user]

    case validate(params) do
      {:ok, ids, "delete", _value} ->
        if Escalated.Permissions.admin?(user),
          do: run(conn, ids, "delete", nil, user),
          else: conn |> put_status(403) |> json(%{error: "Only admins can delete tickets"})

      {:ok, ids, action, value} ->
        run(conn, ids, action, value, user)

      {:error, errors} ->
        conn |> put_status(422) |> json(%{errors: errors})
    end
  end

  defp validate(params) do
    ids = params |> Map.get("ticket_ids") |> parse_ids()
    action = Map.get(params, "action")
    value = Map.get(params, "value")

    errors =
      %{}
      |> check(:ticket_ids, ids in [nil, []], "must list at least one ticket")
      |> check(:ticket_ids, is_list(ids) and length(ids) > @max_tickets, "at most 50 tickets")
      |> check(:action, action not in @actions, "is not a bulk action")
      |> check(:value, action != "delete" and value in [nil, "", []], "can't be blank")

    if errors == %{}, do: {:ok, ids, action, value}, else: {:error, errors}
  end

  defp check(errors, field, true, message), do: Map.put(errors, field, [message])
  defp check(errors, _field, false, _message), do: errors

  defp parse_ids(ids) when is_list(ids) do
    parsed = Enum.map(ids, &parse_id/1)
    if Enum.any?(parsed, &is_nil/1), do: nil, else: Enum.uniq(parsed)
  end

  defp parse_ids(_), do: nil

  defp parse_id(id) when is_integer(id) and id > 0, do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 -> int
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp run(conn, ids, action, value, user) do
    actor_id = Map.get(user || %{}, :id)

    count =
      from(t in Ticket, where: t.id in ^ids)
      |> Escalated.repo().all()
      |> Enum.count(&apply_one(&1, action, value, actor_id))

    noun = if count == 1, do: "ticket", else: "tickets"

    conn
    |> put_flash(:info, "#{count} #{noun} updated.")
    |> redirect(to: back_path(conn))
  end

  defp apply_one(ticket, action, value, actor_id) do
    match?({:ok, _}, change(ticket, action, value, actor_id))
  rescue
    error ->
      Logger.warning(
        "Escalated bulk #{action} skipped ticket ##{ticket.id}: #{Exception.message(error)}"
      )

      false
  end

  defp change(ticket, "status", value, actor_id) do
    value = to_string(value)

    if value in Ticket.statuses(),
      do: TicketService.transition_status(ticket, value, actor_id: actor_id),
      else: :skip
  end

  defp change(ticket, "priority", value, actor_id) do
    value = to_string(value)

    if value in Ticket.priorities(),
      do: TicketService.change_priority(ticket, value, actor_id: actor_id),
      else: :skip
  end

  defp change(ticket, "assign", value, actor_id),
    do: AssignmentService.assign(ticket, value, actor_id: actor_id)

  defp change(ticket, "tags", value, actor_id) do
    case value |> List.wrap() |> parse_ids() do
      nil -> :skip
      tag_ids -> TicketService.add_tags(ticket, tag_ids, actor_id: actor_id)
    end
  end

  defp change(ticket, "department", value, actor_id) do
    with id when not is_nil(id) <- parse_id(value),
         %Department{} = department <- Escalated.repo().get(Department, id) do
      TicketService.change_department(ticket, department, actor_id: actor_id)
    else
      _ -> :skip
    end
  end

  defp change(ticket, "delete", _value, _actor_id), do: Escalated.repo().delete(ticket)

  defp back_path(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> rest = path, query: query} <- URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      if query, do: "#{path}?#{query}", else: path
    else
      _ ->
        prefix = Escalated.config(:route_prefix, "/support")
        area = if String.contains?(conn.request_path, "/admin/"), do: "admin", else: "agent"
        "#{prefix}/#{area}/tickets"
    end
  end
end
