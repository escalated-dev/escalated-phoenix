defmodule Escalated.Services.ChatSessionService do
  @moduledoc """
  Service for managing live chat session lifecycle.

  Handles starting sessions, assigning agents, sending messages,
  ending sessions, and cleaning up idle/abandoned ones.
  """

  alias Escalated.Schemas.{ChatSession, Ticket, Reply}
  alias Escalated.Services.{TicketService, ChatRoutingService}
  alias Escalated.Broadcasting
  import Ecto.Query

  @doc """
  Starts a new chat session.

  Creates a ticket with channel=chat, status=live, and a ChatSession
  in waiting state. Attempts auto-routing to an available agent.
  """
  def start_session(attrs) do
    repo = Escalated.repo()
    guest_token = generate_guest_token()

    subject = attrs[:subject] || attrs["subject"] || "Live Chat"

    ticket_attrs = %{
      subject: subject,
      description: attrs[:message] || attrs["message"] || "",
      status: "live",
      channel: "chat",
      guest_name: attrs[:guest_name] || attrs["guest_name"],
      guest_email: attrs[:guest_email] || attrs["guest_email"],
      guest_token: guest_token,
      requester_type: "guest",
      chat_metadata: %{
        "started_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "page_url" => attrs[:page_url] || attrs["page_url"]
      }
    }

    with {:ok, ticket} <- create_chat_ticket(ticket_attrs),
         {:ok, session} <- create_session(ticket, attrs) do
      # Attempt auto-routing
      case ChatRoutingService.find_available_agent(ticket.department_id) do
        {:ok, agent_id} when not is_nil(agent_id) ->
          {:ok, session} = assign_agent(session, agent_id)
          broadcast_session_started(ticket, session)
          {:ok, ticket, session}

        _ ->
          broadcast_session_started(ticket, session)
          {:ok, ticket, session}
      end
    end
  end

  @doc """
  Assigns an agent to a waiting chat session.
  """
  def assign_agent(session, agent_id) do
    repo = Escalated.repo()
    now = DateTime.utc_now()

    session
    |> ChatSession.changeset(%{
      status: "active",
      agent_id: agent_id,
      agent_joined_at: now
    })
    |> repo.update()
    |> case do
      {:ok, updated} ->
        # Also assign the ticket
        ticket = repo.get!(Ticket, updated.ticket_id)

        ticket
        |> Ticket.changeset(%{assigned_to: agent_id})
        |> repo.update()

        Broadcasting.broadcast_ticket_event("chat:agent_joined", %{
          session_id: updated.id,
          ticket_id: updated.ticket_id,
          agent_id: agent_id
        })

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Sends a chat message (creates a reply on the underlying ticket).
  """
  def send_message(session, body, opts \\ []) do
    repo = Escalated.repo()
    ticket = repo.get!(Ticket, session.ticket_id)
    author_id = Keyword.get(opts, :author_id)
    is_agent = Keyword.get(opts, :is_agent, false)

    reply_attrs = %{
      body: body,
      ticket_id: ticket.id,
      is_internal: false,
      author_id: author_id
    }

    with {:ok, reply} <- TicketService.reply(ticket, reply_attrs) do
      # Update last activity
      session
      |> ChatSession.changeset(%{last_activity_at: DateTime.utc_now()})
      |> repo.update()

      Broadcasting.broadcast_ticket_event("chat:message", %{
        session_id: session.id,
        ticket_id: ticket.id,
        reply_id: reply.id,
        body: reply.body,
        is_agent: is_agent,
        created_at: reply.inserted_at && DateTime.to_iso8601(reply.inserted_at)
      })

      {:ok, reply}
    end
  end

  @doc """
  Ends a chat session and transitions the ticket to open.
  """
  def end_session(session, opts \\ []) do
    repo = Escalated.repo()
    causer_id = Keyword.get(opts, :causer_id)
    now = DateTime.utc_now()

    with {:ok, updated} <-
           session
           |> ChatSession.changeset(%{status: "ended", ended_at: now})
           |> repo.update() do
      ticket = repo.get!(Ticket, updated.ticket_id)

      chat_meta =
        (ticket.chat_metadata || %{})
        |> Map.put("ended_at", DateTime.to_iso8601(now))
        |> Map.put("ended_by", causer_id)
        |> maybe_add_duration(session)

      ticket
      |> Ticket.changeset(%{
        status: "open",
        chat_ended_at: now,
        chat_metadata: chat_meta
      })
      |> repo.update()

      Broadcasting.broadcast_ticket_event("chat:session_ended", %{
        session_id: updated.id,
        ticket_id: ticket.id,
        ended_by: causer_id
      })

      {:ok, updated}
    end
  end

  @doc """
  Lists active and waiting chat sessions.
  """
  def list_active_sessions do
    repo = Escalated.repo()
    repo.all(ChatSession.active() |> order_by([s], asc: s.inserted_at))
  end

  @doc """
  Finds a chat session by ticket ID.
  """
  def find_by_ticket(ticket_id) do
    repo = Escalated.repo()
    repo.one(from(s in ChatSession, where: s.ticket_id == ^ticket_id, order_by: [desc: s.inserted_at], limit: 1))
  end

  @doc """
  Closes idle sessions that have been inactive beyond the threshold.
  """
  def close_idle_sessions(idle_minutes \\ 30) do
    repo = Escalated.repo()
    threshold = DateTime.add(DateTime.utc_now(), -idle_minutes * 60, :second)

    sessions = repo.all(ChatSession.idle_before(threshold))

    Enum.reduce(sessions, 0, fn session, count ->
      case end_session(session) do
        {:ok, _} -> count + 1
        _ -> count
      end
    end)
  end

  @doc """
  Marks sessions as abandoned if they've been waiting too long without an agent.
  """
  def mark_abandoned_sessions(wait_minutes \\ 10) do
    repo = Escalated.repo()
    threshold = DateTime.add(DateTime.utc_now(), -wait_minutes * 60, :second)

    sessions = repo.all(ChatSession.waiting_before(threshold))

    Enum.reduce(sessions, 0, fn session, count ->
      now = DateTime.utc_now()

      with {:ok, _} <-
             session
             |> ChatSession.changeset(%{status: "abandoned", ended_at: now})
             |> repo.update() do
        ticket = repo.get!(Ticket, session.ticket_id)

        ticket
        |> Ticket.changeset(%{status: "open", chat_ended_at: now})
        |> repo.update()

        Broadcasting.broadcast_ticket_event("chat:session_abandoned", %{
          session_id: session.id,
          ticket_id: session.ticket_id
        })

        count + 1
      else
        _ -> count
      end
    end)
  end

  # Private

  defp create_chat_ticket(attrs) do
    repo = Escalated.repo()

    %Ticket{}
    |> Ticket.changeset(attrs)
    |> repo.insert()
  end

  defp create_session(ticket, attrs) do
    repo = Escalated.repo()

    %ChatSession{}
    |> ChatSession.changeset(%{
      ticket_id: ticket.id,
      visitor_ip: attrs[:visitor_ip] || attrs["visitor_ip"],
      visitor_user_agent: attrs[:visitor_user_agent] || attrs["visitor_user_agent"],
      visitor_page_url: attrs[:page_url] || attrs["page_url"],
      last_activity_at: DateTime.utc_now()
    })
    |> repo.insert()
  end

  defp broadcast_session_started(ticket, session) do
    Broadcasting.broadcast_ticket_event("chat:session_started", %{
      session_id: session.id,
      ticket_id: ticket.id,
      ticket_reference: ticket.reference,
      guest_name: ticket.guest_name,
      status: session.status
    })
  end

  defp generate_guest_token do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  defp maybe_add_duration(meta, session) do
    case session.agent_joined_at do
      nil ->
        meta

      joined ->
        now = DateTime.utc_now()
        duration = DateTime.diff(now, joined, :second)
        Map.put(meta, "duration_seconds", duration)
    end
  end
end
