defmodule Escalated.Services.ChatSessionService do
  @moduledoc """
  Service for managing live chat session lifecycle.

  Handles starting sessions, assigning agents, sending messages,
  ending sessions, and cleaning up idle/abandoned ones.
  """

  alias Escalated.Broadcasting
  alias Escalated.Schemas.{ChatSession, Reply, Ticket}
  alias Escalated.Services.{ChatRoutingService, GuestAccess, TicketService}
  import Ecto.Query

  @doc "Creates a chat and consumes email proof in the same transaction."
  def start_guest(params, attrs) do
    address = GuestAccess.email(attrs[:guest_email])
    attrs = Map.put(attrs, :guest_email, address)
    # IP/user-agent are transport details and must not break a legitimate retry.
    identity = Map.drop(attrs, [:visitor_ip, :visitor_user_agent])

    case GuestAccess.consume(Map.put(params, "email", address), "chat", identity, fn ->
           ticket_attrs = %{
             subject: attrs[:subject] || "Live Chat",
             description:
               if(attrs[:message] in [nil, ""], do: "Live chat request", else: attrs[:message]),
             guest_name: attrs[:guest_name],
             guest_email: address,
             guest_token: nil,
             requester_type: "guest",
             status: "live",
             channel: "chat",
             department_id: attrs[:department_id],
             # Host parameters from an embedding page (Escalated.WidgetMetadata).
             metadata: attrs[:metadata] || %{}
           }

           with {:ok, ticket} <- TicketService.insert(ticket_attrs),
                {:ok, session} <- create_session(ticket, attrs) do
             {:ok,
              GuestAccess.issue(ticket, "chat", address) |> Map.put("session_id", session.id)}
           end
         end) do
      {:ok, result} ->
        ticket = Escalated.repo().get!(Ticket, result["ticket_id"])
        session = Escalated.repo().get!(ChatSession, result["session_id"])

        session =
          if not result["_replayed"] do
            activate_guest_session(ticket, session)
          else
            session
          end

        {:ok, ticket, session, result}

      error ->
        error
    end
  end

  defp activate_guest_session(ticket, session) do
    announce("chat.started", session, ticket)

    assigned =
      with {:ok, agent_id} when not is_nil(agent_id) <-
             ChatRoutingService.find_available_agent(ticket.department_id, ticket),
           {:ok, assigned} <- assign_agent(session, agent_id),
           do: assigned

    session = if match?(%ChatSession{}, assigned), do: assigned, else: session
    broadcast_session_started(ticket, session)
    session
  end

  @doc """
  Starts a new chat session.

  Creates a ticket with channel=chat, status=live, and a ChatSession
  in waiting state. Attempts auto-routing to an available agent.
  This is a trusted host operation: its legacy guest_token does not authorize
  public access. Public entry points must use start_guest/2 and mailbox proof.
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
      announce("chat.started", session, ticket)

      # Attempt auto-routing
      case ChatRoutingService.find_available_agent(ticket.department_id, ticket) do
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
    Escalated.TicketVisibility.assert_record!(session)
    repo = Escalated.repo()
    ticket = repo.get!(Ticket, session.ticket_id)

    if not Escalated.TicketVisibility.can_assign?(ticket, agent_id),
      do: Escalated.TicketVisibility.deny!()

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

        ticket =
          case ticket |> Ticket.changeset(%{assigned_to: agent_id}) |> repo.update() do
            {:ok, assigned} -> assigned
            _ -> ticket
          end

        announce("chat.assigned", updated, ticket)

        Broadcasting.broadcast_chat_event("chat:agent_joined", %{
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
  Transfers a chat to another agent and/or department, as escalated-laravel's
  `ChatSessionService::transferChat` does.

  Options: `:to_agent_id` and `:to_department_id` (at least one). With an
  agent, the session and its ticket are reassigned to that agent, who must be
  able to see the ticket. With a department, the ticket moves there; without
  an agent too, the chat goes back to the queue (unassigned, `waiting`) and
  routing looks for an agent in its new department.

  An internal system note records the transfer, so the visitor's transcript
  does not show it. `chat.transferred` adds `from_agent_id`, `to_agent_id` and
  `to_department_id` to the chat payload.

  Returns `{:ok, session}`, `{:error, :no_target}` or
  `{:error, :agent_cannot_access}`.
  """
  def transfer_session(session, opts) do
    to_agent_id = Keyword.get(opts, :to_agent_id)
    to_department_id = Keyword.get(opts, :to_department_id)
    Escalated.TicketVisibility.assert_record!(session)
    repo = Escalated.repo()
    ticket = repo.get!(Ticket, session.ticket_id)

    cond do
      is_nil(to_agent_id) and is_nil(to_department_id) ->
        {:error, :no_target}

      not is_nil(to_agent_id) and
          not Escalated.TicketVisibility.can_assign?(
            %{ticket | department_id: to_department_id || ticket.department_id},
            to_agent_id
          ) ->
        {:error, :agent_cannot_access}

      true ->
        do_transfer(repo, session, ticket, to_agent_id, to_department_id)
    end
  end

  defp do_transfer(repo, session, ticket, to_agent_id, to_department_id) do
    from_agent_id = session.agent_id

    {session_changes, ticket_changes} =
      case {to_agent_id, to_department_id} do
        {nil, department_id} ->
          {%{agent_id: nil, status: "waiting"}, %{assigned_to: nil, department_id: department_id}}

        {agent_id, nil} ->
          {%{agent_id: agent_id}, %{assigned_to: agent_id}}

        {agent_id, department_id} ->
          {%{agent_id: agent_id}, %{assigned_to: agent_id, department_id: department_id}}
      end

    result =
      repo.transaction(fn ->
        with {:ok, updated} <- session |> ChatSession.changeset(session_changes) |> repo.update(),
             {:ok, saved} <- ticket |> Ticket.changeset(ticket_changes) |> repo.update(),
             {:ok, _note} <- transfer_note(repo, saved, to_agent_id, to_department_id) do
          {updated, saved}
        else
          {:error, error} -> repo.rollback(error)
        end
      end)

    with {:ok, {updated, saved}} <- result do
      transfer = %{
        from_agent_id: from_agent_id,
        to_agent_id: to_agent_id,
        to_department_id: to_department_id
      }

      announce("chat.transferred", updated, saved, transfer)

      Broadcasting.broadcast_chat_event(
        "chat:transferred",
        Map.merge(%{session_id: updated.id, ticket_id: updated.ticket_id}, transfer)
      )

      {:ok, maybe_reroute(updated, saved, to_agent_id)}
    end
  end

  defp maybe_reroute(session, _ticket, to_agent_id) when not is_nil(to_agent_id), do: session

  defp maybe_reroute(session, ticket, nil) do
    with {:ok, agent_id} when not is_nil(agent_id) <-
           ChatRoutingService.find_available_agent(ticket.department_id, ticket),
         {:ok, assigned} <- assign_agent(session, agent_id) do
      assigned
    else
      _ -> session
    end
  end

  defp transfer_note(repo, ticket, to_agent_id, to_department_id) do
    department =
      if to_department_id do
        case repo.get(Escalated.Schemas.Department, to_department_id) do
          nil -> "department #{to_department_id}"
          department -> "department #{department.name}"
        end
      end

    agent = if to_agent_id, do: "agent #{to_agent_id}"
    target = [agent, department] |> Enum.reject(&is_nil/1) |> Enum.join(" in ")

    %Reply{}
    |> Reply.changeset(%{
      ticket_id: ticket.id,
      body: "Chat transferred to #{target}.",
      is_internal: true,
      is_system: true,
      author_id: nil
    })
    |> repo.insert()
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

    # Chat messages reach the other side live; they are not emailed.
    with {:ok, reply} <- TicketService.reply(ticket, reply_attrs, notify: false) do
      # Update last activity
      session
      |> ChatSession.changeset(%{last_activity_at: DateTime.utc_now()})
      |> repo.update()

      announce("chat.message", session, ticket, %{
        reply_id: reply.id,
        author_type: if(is_agent, do: "agent", else: "visitor")
      })

      Broadcasting.broadcast_chat_event("chat:message", %{
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

  `:causer_id` is the agent who ended it. `:ended_by` (`"agent"`,
  `"customer"` or `"system"`) is what `chat.ended` reports; it defaults to
  `"agent"` with a causer and `"customer"` without one.
  """
  def end_session(session, opts \\ []) do
    repo = Escalated.repo()
    causer_id = Keyword.get(opts, :causer_id)
    ended_by = Keyword.get(opts, :ended_by, if(causer_id, do: "agent", else: "customer"))
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

      ticket =
        ticket
        |> Ticket.changeset(%{
          status: "open",
          chat_ended_at: now,
          chat_metadata: chat_meta
        })
        |> repo.update()
        |> case do
          {:ok, saved} -> saved
          _ -> ticket
        end

      announce("chat.ended", updated, ticket, %{ended_by: ended_by})

      Broadcasting.broadcast_chat_event("chat:session_ended", %{
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

    repo.one(
      from(s in ChatSession,
        where: s.ticket_id == ^ticket_id,
        order_by: [desc: s.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  Closes idle sessions that have been inactive beyond the threshold.
  """
  def close_idle_sessions(idle_minutes \\ 30) do
    repo = Escalated.repo()
    threshold = DateTime.add(DateTime.utc_now(), -idle_minutes * 60, :second)

    sessions = repo.all(ChatSession.idle_before(threshold))

    Enum.reduce(sessions, 0, fn session, count ->
      case end_session(session, ended_by: "system") do
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

        Broadcasting.broadcast_chat_event("chat:session_abandoned", %{
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

  # Through TicketService.insert/1, which retries a reference collision, but
  # without create/1's side effects: a chat ticket has its own start events.
  defp create_chat_ticket(attrs), do: TicketService.insert(attrs)

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

  # Sends a chat event to webhooks and workflows (Escalated.Events.emit/2).
  # The webhook payload is the :chat map only: never the visitor's chat token,
  # email or message body. Workflows run against the chat's ticket.
  defp announce(event, session, ticket, extra \\ %{}) do
    chat =
      Map.merge(
        %{
          session_id: session.id,
          ticket_id: session.ticket_id,
          status: session.status,
          agent_id: session.agent_id,
          department_id: ticket.department_id
        },
        extra
      )

    Escalated.Events.emit(event, %{ticket: ticket, chat: chat})
  end

  defp broadcast_session_started(ticket, session) do
    Broadcasting.broadcast_chat_event("chat:session_started", %{
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
