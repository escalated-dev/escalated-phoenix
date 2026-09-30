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
  - `"escalated:chat:<ticket_id>"` - live chat events for one session
  - `"escalated:chat:queue"` - chat sessions starting, being taken and ending

  ## Event format

  Events are broadcast as `%{event: event_name, payload: payload}` maps.
  """

  alias Escalated.Tenancy

  # Chat events that change which sessions are waiting or taken, which is what
  # the agents' queue shows.
  @queue_events [
    "chat:session_started",
    "chat:agent_joined",
    "chat:session_ended",
    "chat:session_abandoned"
  ]

  @doc """
  Broadcasts a ticket event if broadcasting is enabled.

  Returns `:ok` if broadcast was sent or broadcasting is disabled.
  """
  def broadcast_ticket_event(event, payload) do
    if enabled?() do
      assert_payload!(payload)
      pubsub = pubsub_server()
      message = %{event: event, payload: payload}

      Phoenix.PubSub.broadcast(pubsub, Tenancy.topic("escalated:tickets"), message)

      # Also broadcast to ticket-specific topic if ticket_id is available
      case payload[:ticket_id] || payload["ticket_id"] do
        nil ->
          :ok

        ticket_id ->
          Phoenix.PubSub.broadcast(
            pubsub,
            Tenancy.topic("escalated:ticket:#{ticket_id}"),
            message
          )
      end

      # Broadcast to agent-specific topic if relevant
      case payload[:agent_id] || payload[:assigned_to] do
        nil ->
          :ok

        agent_id ->
          Phoenix.PubSub.broadcast(pubsub, Tenancy.topic("escalated:agent:#{agent_id}"), message)
      end
    end

    :ok
  end

  @doc """
  Broadcasts a live chat event if broadcasting is enabled.

  Published to the topics `Escalated.Channels.ChatChannel` subscribes to: the
  session's `"escalated:chat:<ticket_id>"` and, for events that change the
  queue, `"escalated:chat:queue"`. It also goes to the ticket topics, as
  `broadcast_ticket_event/2` has always sent chat events there.

  Returns `:ok`.
  """
  def broadcast_chat_event(event, payload) do
    if enabled?() do
      assert_payload!(payload)
      pubsub = pubsub_server()
      message = %{event: event, payload: payload}

      case payload[:ticket_id] do
        nil ->
          :ok

        ticket_id ->
          Phoenix.PubSub.broadcast(pubsub, Tenancy.topic("escalated:chat:#{ticket_id}"), message)
      end

      if event in @queue_events do
        Phoenix.PubSub.broadcast(pubsub, Tenancy.topic("escalated:chat:queue"), message)
      end
    end

    broadcast_ticket_event(event, payload)
  end

  @doc """
  Broadcasts a ticket creation event.
  """
  def ticket_created(ticket) do
    Tenancy.assert_record!(ticket)

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
    Tenancy.assert_record!(ticket)

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
    Tenancy.assert_record!(ticket)
    Tenancy.assert_record!(reply)

    if Tenancy.enabled?() and reply.ticket_id != ticket.id do
      raise ArgumentError, "reply does not belong to the broadcast ticket"
    end

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
  Broadcasts a custom ticket action being triggered.
  """
  def custom_action_triggered(ticket, action_key, user_id, payload, metadata) do
    Tenancy.assert_record!(ticket)

    broadcast_ticket_event("ticket:custom_action_triggered", %{
      ticket_id: ticket.id,
      reference: ticket.reference,
      action: action_key,
      user_id: user_id,
      payload: payload,
      metadata: metadata,
      assigned_to: ticket.assigned_to
    })
  end

  @doc """
  Broadcasts a ticket assignment event.
  """
  def ticket_assigned(ticket, agent_id) do
    Tenancy.assert_record!(ticket)

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
    Tenancy.assert_record!(ticket)

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
      Phoenix.PubSub.subscribe(pubsub_server(), Tenancy.topic("escalated:tickets"))
    else
      :ok
    end
  end

  @doc """
  Subscribes the calling process to events for a specific ticket.
  """
  def subscribe_ticket(ticket_id) do
    if enabled?() do
      assert_payload!(%{ticket_id: ticket_id})
      Phoenix.PubSub.subscribe(pubsub_server(), Tenancy.topic("escalated:ticket:#{ticket_id}"))
    else
      :ok
    end
  end

  @doc """
  Subscribes the calling process to events for a specific agent.
  """
  def subscribe_agent(agent_id) do
    if enabled?() do
      Phoenix.PubSub.subscribe(pubsub_server(), Tenancy.topic("escalated:agent:#{agent_id}"))
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

  defp assert_payload!(payload) do
    if Tenancy.enabled?() do
      id = Map.get(payload, :ticket_id, Map.get(payload, "ticket_id"))

      case id && Escalated.repo().get(Escalated.Schemas.Ticket, id) do
        %Escalated.Schemas.Ticket{} = ticket -> Tenancy.assert_record!(ticket)
        _ -> raise ArgumentError, "broadcast ticket is outside the current tenant"
      end
    end

    :ok
  end
end
