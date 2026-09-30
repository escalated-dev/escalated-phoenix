defmodule Escalated.Controllers.Api.GuestTicketController do
  @moduledoc "Public tickets require mailbox proof and expiring guest capabilities."
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn
  alias Escalated.Controllers.GuestAccessController, as: AccessController
  alias Escalated.Controllers.GuestTicketView
  alias Escalated.Services.{GuestAccess, TicketService}

  def create(conn, params) do
    attrs = %{
      subject: params["subject"],
      description: params["description"] || params["body"],
      guest_name: params["guest_name"] || params["name"],
      guest_email: params["guest_email"] || params["email"],
      priority: params["priority"] || "medium"
    }

    case TicketService.create_guest(params, attrs) do
      {:ok, ticket, result} ->
        conn
        |> put_status(201)
        |> json(%{data: Map.merge(guest_json(ticket), AccessController.public_grant(result))})

      {:error, reason} ->
        AccessController.error(conn, reason)
    end
  end

  # A capability header, when sent, takes precedence over the path segment.
  def show(conn, %{"token" => path_token}) do
    token = GuestAccess.header_token(conn) || path_token

    case GuestAccess.resolve(token) do
      {:ok, ticket, grant} ->
        json(conn, %{data: GuestTicketView.correspondence(ticket, token, grant)})

      _ ->
        AccessController.error(conn, :not_found)
    end
  end

  def reply(conn, %{"token" => path_token} = params) do
    token = GuestAccess.header_token(conn) || path_token

    with {:ok, ticket, _grant} <- GuestAccess.resolve(token),
         {:ok, reply} <- TicketService.reply(ticket, %{body: params["body"], is_internal: false}) do
      conn |> put_status(201) |> json(%{data: %{body: reply.body, created_at: reply.inserted_at}})
    else
      {:error, reason} -> AccessController.error(conn, reason)
    end
  end

  def guest_json(ticket), do: GuestTicketView.summary(ticket)
end
