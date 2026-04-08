defmodule Escalated.Controllers.WidgetChatController do
  @moduledoc """
  Public-facing controller for the widget live chat feature.

  Provides endpoints for checking chat availability, starting
  chat sessions, sending messages, and ending sessions.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Services.{ChatSessionService, ChatAvailabilityService}
  alias Escalated.Schemas.{Ticket, ChatSession}

  @doc """
  Returns chat availability status.
  """
  def availability(conn, _params) do
    status = ChatAvailabilityService.get_status()
    json(conn, %{data: status})
  end

  @doc """
  Starts a new chat session from the widget.
  """
  def start(conn, params) do
    settings = widget_settings()

    unless settings.enabled do
      conn
      |> put_status(403)
      |> json(%{error: "Widget is disabled"})
      |> halt()
    end

    attrs = %{
      guest_name: params["name"],
      guest_email: params["email"],
      subject: params["subject"],
      message: params["message"],
      page_url: params["page_url"],
      visitor_ip: to_string(:inet.ntoa(conn.remote_ip)),
      visitor_user_agent: get_req_header(conn, "user-agent") |> List.first()
    }

    case ChatSessionService.start_session(attrs) do
      {:ok, ticket, session} ->
        conn
        |> put_status(201)
        |> json(%{
          data: %{
            session_id: session.id,
            ticket_reference: ticket.reference,
            guest_token: ticket.guest_token,
            status: session.status
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(422)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc """
  Sends a message in a chat session (guest).
  """
  def send_message(conn, %{"reference" => reference, "body" => body}) do
    guest_token = get_req_header(conn, "x-guest-token") |> List.first()

    case find_session(reference, guest_token) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Session not found"})

      session ->
        case ChatSessionService.send_message(session, body) do
          {:ok, _} ->
            conn |> put_status(201) |> json(%{data: %{status: "sent"}})

          {:error, _} ->
            conn |> put_status(500) |> json(%{error: "Failed to send"})
        end
    end
  end

  @doc """
  Ends a chat session (guest).
  """
  def end_session(conn, %{"reference" => reference}) do
    guest_token = get_req_header(conn, "x-guest-token") |> List.first()

    case find_session(reference, guest_token) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Session not found"})

      session ->
        case ChatSessionService.end_session(session) do
          {:ok, _} -> json(conn, %{data: %{status: "ended"}})
          {:error, _} -> conn |> put_status(500) |> json(%{error: "Failed to end"})
        end
    end
  end

  # Private

  defp find_session(reference, guest_token) when is_binary(guest_token) do
    repo = Escalated.repo()

    case repo.get_by(Ticket, reference: reference, guest_token: guest_token, channel: "chat") do
      nil -> nil
      ticket -> ChatSessionService.find_by_ticket(ticket.id)
    end
  end

  defp find_session(_, _), do: nil

  defp widget_settings do
    defaults = %{
      enabled: true
    }

    configured = Escalated.config(:widget_settings, %{})
    Map.merge(defaults, configured)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
