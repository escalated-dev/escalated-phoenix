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

  @impl true
  def join("escalated:chat:" <> ticket_id, %{"guest_token" => token}, socket) do
    repo = Escalated.repo()

    case repo.get(Escalated.Schemas.Ticket, ticket_id) do
      nil ->
        {:error, %{reason: "not found"}}

      ticket ->
        if ticket.guest_token == token && ticket.channel == "chat" do
          {:ok, socket}
        else
          {:error, %{reason: "unauthorized"}}
        end
    end
  end

  def join("escalated:chat:" <> _ticket_id, _params, socket) do
    # Agent join - check agent auth
    if authorized_agent?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join("escalated:chat:queue", _params, socket) do
    if authorized_agent?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
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
    user = socket.assigns[:current_user]
    check_fn = Escalated.config(:agent_check)

    cond do
      is_nil(user) -> false
      is_function(check_fn, 1) -> check_fn.(user)
      is_nil(check_fn) -> true
      true -> false
    end
  end
end
