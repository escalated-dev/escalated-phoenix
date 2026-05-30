defmodule Escalated.Serializers.TicketSerializer do
  @moduledoc """
  Shared helpers for computing derived ticket fields expected by the frontend.

  The six computed properties are:
    * `requester_name`  — guest name, or the requester user's `name`
    * `requester_email` — guest email, or the requester user's `email`
    * `last_reply_at`   — ISO-8601 timestamp of the most recent reply
    * `last_reply_author` — name of the most recent reply's author
    * `is_live_chat`    — true when status is "live" and channel is "chat"
    * `is_snoozed`      — true when `snoozed_until` is set and in the future

  Detail-only fields (via `detail_fields/1`):
    * `chat_session_id`        — ID of the associated ChatSession
    * `chat_started_at`        — when the chat session was created
    * `chat_messages`          — array of chat message objects
    * `chat_metadata`          — metadata map from the ticket
    * `requester_ticket_count` — total tickets submitted by the requester
    * `related_tickets`        — linked tickets (splits, parent)
    * `subjects`               — host entities the ticket is about
  """

  alias Escalated.Schemas.{Reply, ChatSession, Ticket}
  alias Escalated.Services.TicketSubjectService
  alias Escalated.TicketSubjects
  import Ecto.Query

  @doc """
  Returns a map of the six computed fields for the given ticket.

  The ticket must already have its `replies` association loaded (or an empty
  list will be assumed). If `replies` is not preloaded, the function falls
  back to a single query for the latest reply.
  """
  def computed_fields(ticket) do
    repo = Escalated.repo()
    {requester_name, requester_email} = resolve_requester(ticket, repo)
    {last_reply_at, last_reply_author} = resolve_last_reply(ticket, repo)

    %{
      requester_name: requester_name,
      requester_email: requester_email,
      last_reply_at: last_reply_at,
      last_reply_author: last_reply_author,
      is_live_chat: ticket.status == "live" && ticket.channel == "chat",
      is_snoozed:
        not is_nil(ticket.snoozed_until) &&
          DateTime.compare(ticket.snoozed_until, DateTime.utc_now()) == :gt
    }
  end

  @doc """
  Returns serialized ticket subjects for the UI.
  """
  def subjects(ticket) do
    ticket
    |> TicketSubjectService.list()
    |> TicketSubjects.serialize_links()
  end

  @doc """
  Returns additional computed fields for the ticket detail (show) view.
  """
  def detail_fields(ticket) do
    repo = Escalated.repo()

    chat_session = resolve_chat_session(ticket, repo)
    chat_messages = resolve_chat_messages(ticket, repo)
    requester_ticket_count = resolve_requester_ticket_count(ticket, repo)
    related_tickets = resolve_related_tickets(ticket, repo)

    %{
      chat_session_id: chat_session && chat_session.id,
      chat_started_at:
        chat_session && chat_session.inserted_at && DateTime.to_iso8601(chat_session.inserted_at),
      chat_messages: chat_messages,
      chat_metadata: ticket.chat_metadata,
      requester_ticket_count: requester_ticket_count,
      related_tickets: related_tickets,
      subjects: subjects(ticket)
    }
  end

  @doc """
  Formats a UTC datetime into a human-readable relative string.
  """
  def human_time(nil), do: nil

  def human_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y %H:%M")
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp resolve_requester(ticket, repo) do
    cond do
      # Guest tickets store name/email directly
      ticket.guest_name != nil || ticket.guest_email != nil ->
        {ticket.guest_name, ticket.guest_email}

      # Registered requester — look up via configured user schema
      ticket.requester_id != nil ->
        user_schema = Escalated.user_schema()

        case repo.get(user_schema, ticket.requester_id) do
          nil ->
            {nil, nil}

          user ->
            name =
              if function_exported?(user.__struct__, :name, 1),
                do: user.__struct__.name(user),
                else: Map.get(user, :name)

            email = Map.get(user, :email)
            {name, email}
        end

      true ->
        {nil, nil}
    end
  end

  defp resolve_last_reply(ticket, repo) do
    last_reply =
      from(r in Reply,
        where: r.ticket_id == ^ticket.id,
        order_by: [desc: r.inserted_at],
        limit: 1
      )
      |> repo.one()

    case last_reply do
      nil ->
        {nil, nil}

      reply ->
        at = reply.inserted_at && DateTime.to_iso8601(reply.inserted_at)
        author = resolve_author_name(reply.author_id, repo)
        {at, author}
    end
  end

  defp resolve_author_name(nil, _repo), do: nil

  defp resolve_author_name(author_id, repo) do
    user_schema = Escalated.user_schema()

    case repo.get(user_schema, author_id) do
      nil ->
        nil

      user ->
        if function_exported?(user.__struct__, :name, 1),
          do: user.__struct__.name(user),
          else: Map.get(user, :name)
    end
  end

  defp resolve_chat_session(ticket, repo) do
    if ticket.channel == "chat" do
      repo.one(
        from(s in ChatSession,
          where: s.ticket_id == ^ticket.id,
          order_by: [desc: s.inserted_at],
          limit: 1
        )
      )
    else
      nil
    end
  end

  defp resolve_chat_messages(ticket, repo) do
    if ticket.channel == "chat" do
      replies =
        from(r in Reply,
          where: r.ticket_id == ^ticket.id and r.is_internal == false,
          order_by: [asc: r.inserted_at]
        )
        |> repo.all()

      Enum.map(replies, fn r ->
        %{
          id: r.id,
          body: r.body,
          author_id: r.author_id,
          created_at: r.inserted_at && DateTime.to_iso8601(r.inserted_at)
        }
      end)
    else
      nil
    end
  end

  defp resolve_requester_ticket_count(ticket, repo) do
    cond do
      ticket.requester_id != nil ->
        repo.aggregate(
          from(t in Ticket, where: t.requester_id == ^ticket.requester_id),
          :count
        )

      ticket.guest_email != nil ->
        repo.aggregate(
          from(t in Ticket, where: t.guest_email == ^ticket.guest_email),
          :count
        )

      true ->
        1
    end
  end

  defp resolve_related_tickets(ticket, repo) do
    meta = ticket.metadata || %{}
    related_ids = []

    # Tickets split from this ticket
    split_ids = Map.get(meta, "split_ticket_ids", [])

    # The ticket this was split from
    split_from_id = Map.get(meta, "split_from_ticket_id")
    related_ids = if split_from_id, do: [split_from_id | related_ids], else: related_ids
    related_ids = related_ids ++ split_ids

    if related_ids == [] do
      []
    else
      related_ids
      |> Enum.uniq()
      |> then(fn ids ->
        from(t in Ticket,
          where: t.id in ^ids,
          select: %{id: t.id, reference: t.reference, subject: t.subject, status: t.status}
        )
        |> repo.all()
      end)
    end
  end
end
