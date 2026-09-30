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

  Legacy single-tenant guest users join with a verified guest grant. Agents join
  via their authenticated session. Merchant tenancy requires the host socket's
  trusted `:escalated_tenant_id` assign and an authenticated tenant member.
  """
  use Phoenix.Channel

  alias Escalated.Channels.TenantSocket
  alias Escalated.Schemas.Ticket

  intercept ["chat:typing"]

  @impl true
  def join(topic, params, socket) do
    TenantSocket.run(
      socket,
      fn ->
        topic
        |> TenantSocket.canonical_topic()
        |> do_join(params, socket)
        |> TenantSocket.remember(topic)
      end,
      {:error, %{reason: "unauthorized"}}
    )
  end

  defp do_join("escalated:chat:queue", _params, socket) do
    if authorized_agent?(socket) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp do_join("escalated:chat:" <> ticket_id, params, socket) when is_map(params) do
    with {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 <- Integer.parse(ticket_id),
         %Ticket{channel: "chat"} = ticket <- Escalated.repo().get(Ticket, id) do
      token = params["guest_access_token"] || params["guest_token"]

      cond do
        authorized_agent?(socket) -> {:ok, assign(socket, :escalated_guest_grant, nil)}
        valid_guest_token?(ticket, token) -> {:ok, assign(socket, :escalated_guest_grant, token)}
        true -> {:error, %{reason: "unauthorized"}}
      end
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  defp do_join(_topic, _params, _socket) do
    {:error, %{reason: "invalid topic"}}
  end

  @impl true
  def handle_in("typing", %{"typing" => typing}, socket) do
    deliver(socket, fn ->
      broadcast_from!(socket, "chat:typing", %{typing: typing})
      {:noreply, socket}
    end)
  end

  def handle_in(_, _, socket) do
    deliver(socket, fn -> {:noreply, socket} end)
  end

  @impl true
  def handle_info(%{event: event, payload: payload}, socket) do
    deliver(socket, fn ->
      push(socket, event, payload)
      {:noreply, socket}
    end)
  end

  @impl true
  def handle_out("chat:typing" = event, payload, socket) do
    deliver(socket, fn ->
      push(socket, event, payload)
      {:noreply, socket}
    end)
  end

  defp deliver(socket, callback) do
    TenantSocket.run(
      socket,
      fn ->
        if joined_access?(socket),
          do: callback.(),
          else: {:stop, :normal, socket}
      end,
      {:stop, :normal, socket}
    )
  end

  defp joined_access?(socket) do
    topic = socket |> TenantSocket.joined_topic() |> TenantSocket.canonical_topic()
    params = %{"guest_access_token" => socket.assigns[:escalated_guest_grant]}
    match?({:ok, _}, do_join(topic, params, socket))
  end

  # Private

  defp authorized_agent?(socket) do
    Escalated.Permissions.agent?(socket.assigns[:current_user])
  end

  defp valid_guest_token?(%Ticket{id: id}, supplied)
       when is_binary(supplied) and supplied != "" do
    if Escalated.Tenancy.enabled?() do
      false
    else
      case Escalated.Services.GuestAccess.resolve(supplied, "chat") do
        {:ok, %Ticket{id: ^id}, _grant} -> true
        _ -> false
      end
    end
  end

  defp valid_guest_token?(_ticket, _supplied), do: false
end
