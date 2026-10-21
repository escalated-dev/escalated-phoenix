defmodule Escalated.Controllers.Admin.TicketMergeController do
  @moduledoc """
  The two endpoints the shared `TicketMergeDialog` calls, as escalated-laravel's
  `TicketMergeController` (admin only):

    * `GET {prefix}/admin/tickets/merge-search?q=` (`escalated.admin.tickets.merge-search`)
      answers `{tickets: [%{id, reference, subject, status, created_at}]}`: at
      most ten unmerged tickets whose reference or subject contains `q`.
    * `POST {prefix}/admin/tickets/:reference/merge` with `target_reference`
      (`escalated.admin.tickets.merge`) merges the ticket into the target
      through `Escalated.Services.TicketMergeService` and redirects back with a
      flash. An unknown or already merged target is a 404.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.{TicketMergeService, TicketService}

  @search_limit 10

  def search(conn, params) do
    case params |> Map.get("q") |> to_string() |> String.trim() do
      "" ->
        conn |> put_status(422) |> json(%{errors: %{q: ["can't be blank"]}})

      term ->
        pattern = "%" <> escape_like(String.downcase(term)) <> "%"

        tickets =
          from(t in Ticket,
            where: is_nil(t.merged_into_id),
            where:
              fragment("LOWER(?) LIKE ? ESCAPE '!'", t.reference, ^pattern) or
                fragment("LOWER(?) LIKE ? ESCAPE '!'", t.subject, ^pattern),
            order_by: [desc: t.id],
            limit: @search_limit,
            select: %{
              id: t.id,
              reference: t.reference,
              subject: t.subject,
              status: t.status,
              created_at: t.inserted_at
            }
          )
          |> Escalated.repo().all()

        json(conn, %{tickets: tickets})
    end
  end

  def merge(conn, %{"reference" => reference} = params) do
    target_reference = params |> Map.get("target_reference") |> to_string() |> String.trim()

    with {:source, %Ticket{} = source} <- {:source, TicketService.find(reference)},
         {:target, %Ticket{merged_into_id: nil} = target} <-
           {:target, find_by_reference(target_reference)} do
      case TicketMergeService.merge(source, target, actor_id: actor_id(conn)) do
        {:ok, _} ->
          back(conn, source, :info, "Ticket merged into #{target.reference}.")

        {:error, :same_ticket} ->
          back(conn, source, :error, "Cannot merge a ticket into itself.")

        {:error, :already_merged} ->
          back(conn, source, :error, "This ticket has already been merged.")

        {:error, _} ->
          back(conn, source, :error, "The tickets could not be merged.")
      end
    else
      {:source, nil} -> not_found(conn, "Ticket not found")
      {:target, _} -> not_found(conn, "Target ticket not found")
    end
  end

  # By reference only, as the dialog sends it (the numeric-id fallback of
  # TicketService.find/1 would let a typed number name some other ticket).
  defp find_by_reference(""), do: nil
  defp find_by_reference(reference), do: Escalated.repo().get_by(Ticket, reference: reference)

  # `!` escapes LIKE wildcards on every adapter: a backslash means different
  # things in SQLite, PostgreSQL and MySQL string literals.
  defp escape_like(term) do
    term
    |> String.replace("!", "!!")
    |> String.replace("%", "!%")
    |> String.replace("_", "!_")
  end

  defp actor_id(conn) do
    case conn.assigns[:current_user] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp back(conn, ticket, kind, message) do
    conn |> put_flash(kind, message) |> redirect(to: back_path(conn, ticket))
  end

  defp back_path(conn, ticket) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{path: "/" <> rest = path, query: query} <- URI.parse(referer),
         false <- String.starts_with?(rest, "/") do
      if query, do: "#{path}?#{query}", else: path
    else
      _ -> "#{Escalated.config(:route_prefix, "/support")}/admin/tickets/#{ticket.reference}"
    end
  end

  defp not_found(conn, message), do: conn |> put_status(404) |> json(%{error: message})
end
