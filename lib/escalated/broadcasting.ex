defmodule Escalated.Broadcasting do
  @moduledoc """
  Real-time broadcasting for Escalated events via Phoenix PubSub.

  When `broadcasting_enabled` is `true` and a `pubsub_server` is configured,
  this module broadcasts events on well-known topics so that Phoenix Channels
  or LiveView processes can subscribe and react.

  ## Configuration

      config :escalated,
        broadcasting_enabled: true,
        pubsub_server: MyApp.PubSub

  ## Topics

  - `"escalated:tickets"` - all ticket events (create, update, status change, etc.)
  - `"escalated:ticket:<id>"` - events for a specific ticket
  - `"escalated:agent:<agent_id>"` - events relevant to a specific agent

  ## Event format

  Events are broadcast as `%{event: event_name, payload: payload}` maps.
  """

  @doc """
  Broadcasts a ticket event if broadcasting is enabled.

  Returns `:ok` if broadcast was sent or broadcasting is disabled.
  """
  def broadcast_ticket_event(event, payload) do
    if enabled?() do
      pubsub = pubsub_server()
      topic = "escalated:tickets"

      Phoenix.PubSub.broadcast(pubsub, topic, %{event: event, payload: payload})

      # Also broadcast to ticket-specific topic if ticket_id is available
      if ticket_id = payload[:ticket_id] || payload["ticket_id"] do
        Phoenix.PubSub.broadcast(pubsub, "escalated:ticket:#{ticket_id}", %{
          event: event,
          payload: payload
        })
      end

      # Broadcast to agent-specific topic if relevant
      if agent_id = payload[:agent_id] || payload[:assigned_to] do
        Phoenix.PubSub.broadcast(pubsub, "escalated:agent:#{agent_id}", %{
          event: event,
          payload: payload
        })
      end

      :ok
    else
      :ok
    end
  end

  @doc """
  Broadcasts a ticket creation event.
  """
  def ticket_created(ticket) do
    broadcast_ticket_event("ticket:created", %{
      ticket_id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject,
      status: ticket.status,
      priority: ticket.priority,
      assigned_to: ticket.assigned_to
    })
  end

  @doc """
  Broadcasts a ticket status change event.
  """
  def ticket_status_changed(ticket, from_status, to_status) do
    broadcast_ticket_event("ticket:status_changed", %{
      ticket_id: ticket.id,
      reference: ticket.reference,
      from: from_status,
      to: to_status,
      assigned_to: ticket.assigned_to
    })
  end

  @doc """
  Broadcasts a new reply event.
  """
  def reply_added(ticket, reply) do
    broadcast_ticket_event("ticket:reply_added", %{
      ticket_id: ticket.id,
      reference: ticket.reference,
      reply_id: reply.id,
      is_internal: reply.is_internal,
      author_id: reply.author_id,
      assigned_to: ticket.assigned_to
    })
  end

  @doc """
  Broadcasts a ticket assignment event.
  """
  def ticket_assigned(ticket, agent_id) do
    broadcast_ticket_event("ticket:assigned", %{
      ticket_id: ticket.id,
      reference: ticket.reference,
      agent_id: agent_id,
      assigned_to: agent_id
    })
  end

  @doc """
  Broadcasts a ticket priority change event.
  """
  def ticket_priority_changed(ticket, from_priority, to_priority) do
    broadcast_ticket_event("ticket:priority_changed", %{
      ticket_id: ticket.id,
      reference: ticket.reference,
      from: from_priority,
      to: to_priority,
      assigned_to: ticket.assigned_to
    })
  end

  @doc """
  Subscribes the calling process to all ticket events.
  """
  def subscribe_tickets do
    if enabled?() do
      Phoenix.PubSub.subscribe(pubsub_server(), "escalated:tickets")
    else
      :ok
    end
  end

  @doc """
  Subscribes the calling process to events for a specific ticket.
  """
  def subscribe_ticket(ticket_id) do
    if enabled?() do
      Phoenix.PubSub.subscribe(pubsub_server(), "escalated:ticket:#{ticket_id}")
    else
      :ok
    end
  end

  @doc """
  Subscribes the calling process to events for a specific agent.
  """
  def subscribe_agent(agent_id) do
    if enabled?() do
      Phoenix.PubSub.subscribe(pubsub_server(), "escalated:agent:#{agent_id}")
    else
      :ok
    end
  end

  @doc """
  Returns whether broadcasting is enabled and properly configured.
  """
  def enabled? do
    config = Escalated.configuration()
    Escalated.Config.broadcasting_enabled?(config) && pubsub_server() != nil
  end

  @doc """
  Returns the configured PubSub server module.
  """
  def pubsub_server do
    Escalated.config(:pubsub_server)
  end
end
