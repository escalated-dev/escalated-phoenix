defmodule Escalated.Controllers.Api.GuestTicketController do
  @moduledoc """
  Public JSON endpoints for anonymous (guest) ticket submission and
  lookup — part of the general `/api/v1` surface the Flutter app consumes.
  A guest token is minted on create and used to fetch the ticket later.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Schemas.Ticket
  alias Escalated.Services.TicketService

  def create(conn, params) do
    token = generate_guest_token()

    # Atom keys: TicketService.create injects an atom `:contact_id` during
    # guest contact resolution, so the attrs map must be atom-keyed too
    # (Ecto rejects mixed string/atom keys).
    attrs = %{
      subject: params["subject"],
      description: params["description"] || params["body"],
      guest_name: params["guest_name"] || params["name"],
      guest_email: params["guest_email"] || params["email"],
      guest_token: token,
      priority: params["priority"] || "medium"
    }

    case TicketService.create(attrs) do
      {:ok, ticket} ->
        conn |> put_status(201) |> json(%{data: guest_json(ticket)})

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{errors: format_errors(changeset)})
    end
  end

  def show(conn, %{"token" => token}) do
    case Escalated.repo().get_by(Ticket, guest_token: token) do
      nil -> conn |> put_status(404) |> json(%{error: "Ticket not found"})
      ticket -> json(conn, %{data: guest_json(ticket)})
    end
  end

  defp guest_json(ticket) do
    %{
      id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject,
      status: ticket.status,
      priority: ticket.priority,
      guest_token: ticket.guest_token,
      guest_name: ticket.guest_name,
      guest_email: ticket.guest_email,
      created_at: ticket.inserted_at && DateTime.to_iso8601(ticket.inserted_at)
    }
  end

  defp generate_guest_token do
    20 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
