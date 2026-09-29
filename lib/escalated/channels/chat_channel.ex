defmodule Escalated.Channels.ChatChannel do
  @moduledoc """
  Phoenix Channel for real-time live chat updates.

  ## Topics

  - `"escalated:chat:<ticket_id>"` - events for a specific chat session
  - `"escalated:chat:queue"` - agent-facing queue updates (new sessions, etc.)

  ## Events

  - `"chat:message"` - new chat message
  - `"chat:agent_joined"` - agent accepted the session
  - `"chat:session_ended"` - session was ended
  - `"chat:session_started"` - new session in the queue
  - `"chat:typing"` - typing indicator

  ## Authorization

  Guest users join via their guest token. Agents join via their authenticated session.
  """
  use Phoenix.Channel

  alias Escalated.Schemas.Ticket

  @impl true
  def join("escalated:chat:queue", _params, socket) do
    if authorized_agent?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("escalated:chat:" <> ticket_id, params, socket) when is_map(params) do
    with {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(ticket_id),
         %Ticket{channel: "chat"} = ticket <- Escalated.repo().get(Ticket, id),
         true <- authorized_agent?(socket) or valid_guest_token?(ticket, params["guest_token"]) do
      {:ok, socket}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  def join(_topic, _params, _socket) do
    {:error, %{reason: "invalid topic"}}
  end

  @impl true
  def handle_in("typing", %{"typing" => typing}, socket) do
    broadcast_from!(socket, "chat:typing", %{typing: typing})
    {:noreply, socket}
  end

  def handle_in(_, _, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end

  # Private

  defp authorized_agent?(socket) do
    Escalated.Permissions.agent?(socket.assigns[:current_user])
  end

  defp valid_guest_token?(%Ticket{guest_token: stored}, supplied)
       when is_binary(stored) and stored != "" and is_binary(supplied) and supplied != "",
       do: Plug.Crypto.secure_compare(stored, supplied)

  defp valid_guest_token?(_ticket, _supplied), do: false
end
