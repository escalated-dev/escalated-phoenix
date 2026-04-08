defmodule Escalated.Controllers.Agent.ChatController do
  @moduledoc """
  Agent-facing controller for managing live chat sessions.

  Provides endpoints to list active sessions, accept waiting chats,
  send messages, and end sessions.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Services.ChatSessionService

  @doc """
  Lists active and waiting chat sessions.
  """
  def sessions(conn, _params) do
    sessions = ChatSessionService.list_active_sessions()
    repo = Escalated.repo()

    data =
      Enum.map(sessions, fn session ->
        ticket = repo.get!(Escalated.Schemas.Ticket, session.ticket_id)

        %{
          id: session.id,
          status: session.status,
          agent_id: session.agent_id,
          ticket_reference: ticket.reference,
          guest_name: ticket.guest_name,
          created_at: session.inserted_at && DateTime.to_iso8601(session.inserted_at)
        }
      end)

    json(conn, %{data: data})
  end

  @doc """
  Accepts a waiting chat session.
  """
  def accept(conn, %{"id" => ticket_id}) do
    case ChatSessionService.find_by_ticket(ticket_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Session not found"})

      session ->
        if Escalated.Schemas.ChatSession.waiting?(session) do
          agent_id = conn.assigns[:current_user].id

          case ChatSessionService.assign_agent(session, agent_id) do
            {:ok, _} -> json(conn, %{data: %{status: "accepted"}})
            {:error, _} -> conn |> put_status(500) |> json(%{error: "Failed to accept"})
          end
        else
          conn |> put_status(409) |> json(%{error: "Session is not waiting"})
        end
    end
  end

  @doc """
  Sends a message in an active chat session.
  """
  def send_message(conn, %{"id" => ticket_id, "body" => body}) do
    case ChatSessionService.find_by_ticket(ticket_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Active session not found"})

      session ->
        if Escalated.Schemas.ChatSession.active?(session) do
          agent_id = conn.assigns[:current_user].id

          case ChatSessionService.send_message(session, body, author_id: agent_id, is_agent: true) do
            {:ok, _} ->
              conn |> put_status(201) |> json(%{data: %{status: "sent"}})

            {:error, _} ->
              conn |> put_status(500) |> json(%{error: "Failed to send"})
          end
        else
          conn |> put_status(404) |> json(%{error: "Active session not found"})
        end
    end
  end

  @doc """
  Ends a chat session.
  """
  def end_session(conn, %{"id" => ticket_id}) do
    case ChatSessionService.find_by_ticket(ticket_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Session not found"})

      session ->
        agent_id = conn.assigns[:current_user].id

        case ChatSessionService.end_session(session, causer_id: agent_id) do
          {:ok, _} -> json(conn, %{data: %{status: "ended"}})
          {:error, _} -> conn |> put_status(500) |> json(%{error: "Failed to end session"})
        end
    end
  end
end
