defmodule Escalated.Channels.TenantChannel do
  @moduledoc """
  Dispatches tenant-scoped realtime topics to ticket and chat channels.

  Register this in the host socket, alongside its legacy channel registrations:

      channel "escalated:tenant:*", Escalated.Channels.TenantChannel

  The host's authenticated `connect/3` must assign `:current_user` and
  `:escalated_tenant_id` from trusted session/routing state. Never copy either
  identity directly from client parameters. Clients use the shared Inertia
  `escalated.broadcasting.channel_prefix` when constructing their topics.

  Each delegated channel rechecks membership and access before handling or
  delivering a message. Guest sockets are denied while merchant tenancy is on.
  """
  use Phoenix.Channel

  alias Escalated.Channels.{ChatChannel, TenantSocket, TicketChannel}

  intercept ["chat:typing"]

  @impl true
  def join(topic, params, socket) do
    TenantSocket.run(
      socket,
      fn ->
        channel =
          case TenantSocket.canonical_topic(topic) do
            "escalated:chat:" <> _ -> ChatChannel
            "escalated:" <> _ -> TicketChannel
            _ -> nil
          end

        if channel do
          case channel.join(topic, params, socket) do
            {:ok, joined} -> {:ok, assign(joined, :escalated_channel, channel)}
            error -> error
          end
        else
          {:error, %{reason: "unauthorized"}}
        end
      end,
      {:error, %{reason: "unauthorized"}}
    )
  end

  @impl true
  def handle_in(event, payload, socket) do
    case socket.assigns[:escalated_channel] do
      channel when channel in [ChatChannel, TicketChannel] ->
        channel.handle_in(event, payload, socket)

      _ ->
        {:stop, :normal, socket}
    end
  end

  @impl true
  def handle_info(message, socket) do
    case socket.assigns[:escalated_channel] do
      channel when channel in [ChatChannel, TicketChannel] -> channel.handle_info(message, socket)
      _ -> {:stop, :normal, socket}
    end
  end

  @impl true
  def handle_out("chat:typing" = event, payload, socket) do
    case socket.assigns[:escalated_channel] do
      ChatChannel -> ChatChannel.handle_out(event, payload, socket)
      _ -> {:stop, :normal, socket}
    end
  end
end
