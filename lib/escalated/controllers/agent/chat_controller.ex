defmodule Escalated.Controllers.Agent.ChatController do
  @moduledoc """
  Agent-facing controller for managing live chat sessions.

  Provides endpoints to list active sessions, accept waiting chats,
  send messages, and end sessions.
  """
  use Phoenix.Controller, formats: [:json]
  import Plug.Conn

  alias Escalated.Schemas.ChatSession
  alias Escalated.Services.ChatSessionService

  @user_id_type Application.compile_env(:escalated, :user_key_type, :integer)

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
  Transfers a chat to another agent and/or department (escalated-laravel
  `escalated.admin.chat.transfer`).

  The body is `{"agent_id", "department_id"}` (either or both). The shared
  `ChatActionBar`'s `{"type": "agent" | "department", "id"}` is read too.
  """
  def transfer(conn, %{"id" => ticket_id} = params) do
    case ChatSessionService.find_by_ticket(ticket_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Session not found"})

      session ->
        if ChatSession.active?(session) or ChatSession.waiting?(session) do
          transfer_open_session(conn, session, ticket_id, params)
        else
          unprocessable(conn, "Chat is already ended.")
        end
    end
  end

  defp transfer_open_session(conn, session, ticket_id, params) do
    params = action_bar_params(conn, params)

    with {:ok, agent_id} <- cast_id(@user_id_type, params["agent_id"], "agent_id"),
         {:ok, department_id} <- cast_id(:id, params["department_id"], "department_id"),
         :ok <- department_exists(department_id),
         {:ok, _} <-
           ChatSessionService.transfer_session(session,
             to_agent_id: agent_id,
             to_department_id: department_id
           ) do
      json(conn, %{
        message: "Chat transferred.",
        session: session_json(ChatSessionService.find_by_ticket(ticket_id))
      })
    else
      {:invalid, message} -> unprocessable(conn, message)
      {:error, :no_target} -> unprocessable(conn, "Provide an agent_id or department_id.")
      {:error, :agent_cannot_access} -> unprocessable(conn, "The agent cannot access this chat.")
      {:error, _} -> conn |> put_status(500) |> json(%{error: "Failed to transfer"})
    end
  end

  # The route's :id (the chat ticket) shadows a body "id" in params, so the
  # ChatActionBar's target is read from the body itself.
  defp action_bar_params(conn, params) do
    body = if is_map(conn.body_params), do: conn.body_params, else: %{}

    case body do
      %{"type" => "agent", "id" => id} -> Map.put_new(params, "agent_id", id)
      %{"type" => "department", "id" => id} -> Map.put_new(params, "department_id", id)
      _ -> params
    end
  end

  defp cast_id(_type, value, _field) when value in [nil, ""], do: {:ok, nil}

  defp cast_id(type, value, field) do
    case Ecto.Type.cast(type, value) do
      {:ok, id} -> {:ok, id}
      _ -> {:invalid, "The #{field} is invalid."}
    end
  end

  defp department_exists(nil), do: :ok

  defp department_exists(id) do
    if Escalated.repo().get(Escalated.Schemas.Department, id),
      do: :ok,
      else: {:invalid, "The selected department_id is invalid."}
  end

  defp unprocessable(conn, message),
    do: conn |> put_status(422) |> json(%{message: message})

  defp session_json(session) do
    %{
      id: session.id,
      ticket_id: session.ticket_id,
      status: session.status,
      agent_id: session.agent_id
    }
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

  @doc """
  Ends a chat by its ChatSession id (escalated-laravel
  `escalated.admin.chat.end`, `POST /agent/chat/:session/end`). The shared
  ticket page posts `{}` here with its `chat_session_id`.

  404 for an unknown session, 422 `{"message": "Chat is already ended."}` when
  it is no longer waiting or active, otherwise 200 `{"message": "Chat ended."}`.
  """
  def end_chat(conn, %{"session" => session_id}) do
    with {:ok, id} <- Ecto.Type.cast(:id, session_id),
         %ChatSession{} = session <- Escalated.repo().get(ChatSession, id) do
      end_open_chat(conn, session)
    else
      _ -> conn |> put_status(404) |> json(%{message: "Chat session not found."})
    end
  end

  defp end_open_chat(conn, session) do
    if ChatSession.active?(session) or ChatSession.waiting?(session) do
      case ChatSessionService.end_session(session, causer_id: conn.assigns[:current_user].id) do
        {:ok, _} -> json(conn, %{message: "Chat ended."})
        {:error, _} -> conn |> put_status(500) |> json(%{message: "Failed to end chat."})
      end
    else
      unprocessable(conn, "Chat is already ended.")
    end
  end
end
