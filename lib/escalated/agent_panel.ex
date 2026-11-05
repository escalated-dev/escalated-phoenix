defmodule Escalated.AgentPanel do
  @moduledoc """
  The agent panel's data (escalated-developer-context ADR
  2026-11-05-agent-panel-data), after escalated-laravel #292-#296:

    * the agent's own status (`agent_profiles.chat_status`);
    * per-agent unread markers (`ticket_reads` against
      `tickets.last_customer_activity_at`);
    * customer presence (`customer_presence`), shown on agent pages only;
    * the agents' in-app notifications (`notifications`).

  `Escalated.Events.emit/2` hands every event to `on_event/2`. Nothing here
  can fail the operation that emitted it: event handling and presence log and
  swallow their own errors.
  """
  import Ecto.Query

  require Logger

  alias Escalated.{Broadcasting, Permissions, TicketVisibility}
  alias Escalated.Schemas.{AgentNotification, AgentProfile, CustomerPresence, Reply}
  alias Escalated.Schemas.{Ticket, TicketRead}
  alias Escalated.Services.Followers

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")
  @reads @prefix <> "ticket_reads"

  # A ticket is unread for an agent who marked it unread, or when the
  # customer was active on it after the agent last read it. Raw SQL rather
  # than an Ecto subquery: the tenancy and visibility scopes refuse subqueries
  # and left joins, and `ticket_reads` rows are keyed by the (globally unique)
  # ticket id, so the check cannot reach another tenant's rows. The table name
  # is quoted (a prefix may have capitals), with MySQL's quote character there.
  @unread_sql_template "(EXISTS (SELECT 1 FROM {reads} ur WHERE ur.ticket_id = ? " <>
                         "AND ur.user_id = ? AND ur.last_read_at IS NULL) " <>
                         "OR (? IS NOT NULL AND NOT EXISTS (SELECT 1 FROM {reads} ur " <>
                         "WHERE ur.ticket_id = ? AND ur.user_id = ? " <>
                         "AND ur.last_read_at >= ?)))"
  @unread_sql String.replace(@unread_sql_template, "{reads}", ~s("#{@reads}"))
  @unread_sql_mysql String.replace(@unread_sql_template, "{reads}", "`#{@reads}`")

  @statuses ~w(online away offline)
  @throttle_seconds 30
  @default_window 120

  @titles %{
    "ticket_assigned" => "%{reference} was assigned to you",
    "ticket_reply" => "New reply on %{reference}",
    "mention" => "%{name} mentioned you in %{reference}",
    "sla_warning" => "SLA due soon on %{reference}",
    "sla_breached" => "SLA breached on %{reference}",
    "chat_transferred" => "A chat was transferred to you (%{reference})",
    "generic" => "Update on %{reference}"
  }
  @unavailable "A ticket you can no longer view"

  # --- Agent status -----------------------------------------------------

  @doc "The statuses an agent may set: online, away and offline."
  def statuses, do: @statuses

  @doc "The agent's status, `offline` until they set one."
  def status(nil), do: "offline"

  def status(user) do
    from(p in AgentProfile, where: p.user_id == ^user.id, select: p.chat_status, limit: 1)
    |> Escalated.repo().one()
    |> case do
      status when status in @statuses -> status
      _ -> "offline"
    end
  end

  @doc "Stores the agent's status on their agent profile, creating it if needed."
  def set_status(user, status) when status in @statuses do
    repo = Escalated.repo()
    now = now()

    {count, _} =
      from(p in AgentProfile, where: p.user_id == ^user.id)
      |> repo.update_all(set: [chat_status: status, updated_at: now])

    if count == 0 do
      repo.insert!(%AgentProfile{user_id: user.id, chat_status: status})
    end

    :ok
  end

  # --- Unread markers ---------------------------------------------------

  @doc "Marks the ticket read for the agent."
  def mark_read(user_id, %Ticket{} = ticket), do: put_read(user_id, ticket, now())

  @doc "Marks the ticket unread for the agent until they open it again."
  def mark_unread(user_id, %Ticket{} = ticket), do: put_read(user_id, ticket, nil)

  # An update, then an insert when there was no row: the ticket visibility
  # scope refuses upserts that replace columns. A concurrent insert of the
  # same row is ignored and the update runs again.
  defp put_read(user_id, ticket, read_at) do
    repo = Escalated.repo()
    user_id = to_string(user_id)
    now = now()

    query = from(r in TicketRead, where: r.ticket_id == ^ticket.id and r.user_id == ^user_id)
    set = [set: [last_read_at: read_at, updated_at: now]]

    with {0, _} <- repo.update_all(query, set) do
      %TicketRead{ticket_id: ticket.id, user_id: user_id, last_read_at: read_at}
      |> repo.insert(Escalated.Repo.ignore_duplicates([:user_id, :ticket_id]))

      repo.update_all(query, set)
    end

    :ok
  end

  @doc """
  Narrows a ticket query to the tickets unread for `user_id` (the inbox's
  `unread` counts). The query's ticket binding must be the first one.
  """
  def only_unread(query, user_id) do
    me = to_string(user_id)

    if Escalated.repo().__adapter__() == Ecto.Adapters.MyXQL do
      where(
        query,
        [t],
        fragment(
          unquote(@unread_sql_mysql),
          t.id,
          ^me,
          t.last_customer_activity_at,
          t.id,
          ^me,
          t.last_customer_activity_at
        )
      )
    else
      where(
        query,
        [t],
        fragment(
          unquote(@unread_sql),
          t.id,
          ^me,
          t.last_customer_activity_at,
          t.id,
          ^me,
          t.last_customer_activity_at
        )
      )
    end
  end

  @doc """
  `is_unread`, `requester_online` and `requester_last_seen_at` for each of
  `tickets` (structs), keyed by ticket id: one query for the markers and one
  for presence, whatever the page size.
  """
  def row_fields(_user, []), do: %{}

  def row_fields(user, tickets) do
    unread = unread_flags(user.id, tickets)
    presence = presence(tickets)

    Map.new(tickets, fn ticket ->
      {ticket.id, Map.put(Map.fetch!(presence, ticket.id), :is_unread, unread[ticket.id])}
    end)
  end

  @doc "Whether each ticket is unread for `user_id`, keyed by ticket id."
  def unread_flags(user_id, tickets) do
    ids = Enum.map(tickets, & &1.id)

    reads =
      from(r in TicketRead,
        where: r.user_id == ^to_string(user_id) and r.ticket_id in ^ids,
        select: {r.ticket_id, r.last_read_at}
      )
      |> Escalated.repo().all()
      |> Map.new()

    Map.new(tickets, fn ticket ->
      {ticket.id, unread?(Map.fetch(reads, ticket.id), ticket.last_customer_activity_at)}
    end)
  end

  defp unread?({:ok, nil}, _activity), do: true
  defp unread?(_read, nil), do: false
  defp unread?(:error, _activity), do: true
  defp unread?({:ok, read_at}, activity), do: DateTime.compare(read_at, activity) == :lt

  @doc """
  Whether `reply` came from the customer side: a public reply by the
  requester, a guest or an inbound email (no author), or a user who is not
  staff. Agents' replies, internal notes, system replies and replies a
  workflow writes (`author: :system`) are not.
  """
  def customer_side?(%Ticket{} = ticket, %Reply{} = reply, context \\ %{}) do
    cond do
      reply.is_internal or reply.is_system -> false
      Map.get(context, :author) == :system -> false
      is_nil(reply.author_id) -> true
      requester?(ticket, reply.author_id) -> true
      true -> not staff?(reply.author_id)
    end
  end

  defp requester?(%Ticket{requester_type: type}, _id) when type in ["guest", "contact"], do: false
  defp requester?(%Ticket{requester_id: nil}, _id), do: false
  defp requester?(%Ticket{requester_id: id}, author_id), do: to_string(id) == to_string(author_id)

  defp staff?(user_id), do: Permissions.agent?(TicketVisibility.load_user(user_id))

  defp customer_activity(ticket, reply) do
    at = reply.inserted_at || now()

    from(t in Ticket, where: t.id == ^ticket.id)
    |> Escalated.repo().update_all(set: [last_customer_activity_at: at])
  end

  # --- Customer presence ------------------------------------------------

  @doc "Records that the signed-in customer is on the site, at most every 30 seconds."
  def see_user(user), do: see({"user", to_string(user.id)})

  @doc "Records that a ticket's customer (requester, contact or guest) is on the site."
  def see_ticket_customer(%Ticket{} = ticket), do: see(subject(ticket))

  @doc "Runs `fun`, logging and swallowing any error: presence never fails a request."
  def quietly(fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.warning("Escalated agent panel: #{Exception.message(error)}")
      :ok
  end

  defp see({type, id}) do
    repo = Escalated.repo()
    now = now()
    cutoff = DateTime.add(now, -@throttle_seconds, :second)

    {count, _} =
      from(p in CustomerPresence,
        where: p.subject_type == ^type and p.subject_id == ^id and p.last_seen_at < ^cutoff
      )
      |> repo.update_all(set: [last_seen_at: now, updated_at: now])

    if count == 0 do
      %CustomerPresence{subject_type: type, subject_id: id, last_seen_at: now}
      |> repo.insert(Escalated.Repo.ignore_duplicates([:subject_type, :subject_id]))
    end

    :ok
  end

  # The requester for a user ticket, else the contact, else the ticket itself
  # (a guest chat with neither).
  defp subject(%Ticket{requester_id: id, requester_type: type})
       when not is_nil(id) and type not in ["guest", "contact", "Contact"],
       do: {"user", to_string(id)}

  defp subject(%Ticket{contact_id: id}) when not is_nil(id), do: {"contact", to_string(id)}
  defp subject(%Ticket{id: id}), do: {"ticket", to_string(id)}

  defp presence(tickets) do
    subjects = Map.new(tickets, &{&1.id, subject(&1)})
    ids = subjects |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    seen =
      from(p in CustomerPresence,
        where: p.subject_id in ^ids,
        select: {{p.subject_type, p.subject_id}, p.last_seen_at}
      )
      |> Escalated.repo().all()
      |> Map.new()

    online_after = DateTime.add(now(), -online_window(), :second)

    Map.new(subjects, fn {ticket_id, subject} ->
      last_seen = Map.get(seen, subject)

      {ticket_id,
       %{
         requester_online:
           not is_nil(last_seen) and DateTime.compare(last_seen, online_after) != :lt,
         requester_last_seen_at: last_seen
       }}
    end)
  end

  defp online_window do
    case Escalated.config(:presence_online_window_seconds, @default_window) do
      seconds when is_integer(seconds) and seconds > 0 -> seconds
      _ -> @default_window
    end
  end

  # --- Notifications ----------------------------------------------------

  @doc "Whether the in-app notifications feed is on (`config :escalated, agent_notifications:`)."
  def notifications_enabled?,
    do: Escalated.config(:agent_notifications, true) not in [false, "false"]

  @doc """
  Handles a domain event (`Escalated.Events.emit/2`): customer activity for
  unread markers, and the in-app notifications. Always returns `:ok`.
  """
  def on_event(event, context) do
    handle(event, context)
    :ok
  rescue
    error ->
      Logger.warning("Escalated agent panel #{event} failed: #{Exception.message(error)}")
      :ok
  end

  defp handle("reply.created", %{ticket: %Ticket{} = ticket, reply: %Reply{} = reply} = context) do
    if customer_side?(ticket, reply, context) do
      customer_activity(ticket, reply)

      [ticket.assigned_to | Followers.follower_user_ids(ticket.id, reply.author_id)]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(&to_string/1)
      |> Enum.each(&notify(&1, "ticket_reply", ticket, %{reply_id: reply.id}, reply.author_id))
    end
  end

  defp handle("ticket.assigned", %{ticket: %Ticket{} = ticket, agent_id: agent_id} = context),
    do: notify(agent_id, "ticket_assigned", ticket, %{}, Map.get(context, :actor_id))

  defp handle("sla.warning", %{ticket: %Ticket{} = ticket}),
    do: notify(ticket.assigned_to, "sla_warning", ticket, %{}, nil)

  defp handle("sla.breached", %{ticket: %Ticket{} = ticket} = context),
    do: notify(ticket.assigned_to, "sla_breached", ticket, sla_type(context), nil)

  defp handle("chat.transferred", %{ticket: %Ticket{} = ticket, chat: chat}) do
    notify(
      Map.get(chat, :to_agent_id),
      "chat_transferred",
      ticket,
      %{session_id: Map.get(chat, :session_id)},
      Map.get(chat, :from_agent_id)
    )
  end

  defp handle(_event, _context), do: :ok

  defp sla_type(context), do: %{sla_type: Map.get(context, :breach_type)}

  @doc """
  Stores an in-app notification for `user_id` about `ticket` and broadcasts
  it as `notification.created`. Nobody is notified of their own action
  (`causer_id`), and nothing is stored while the feed is off.
  """
  def notify(user_id, type, %Ticket{} = ticket, extra, causer_id) do
    cond do
      is_nil(user_id) or not notifications_enabled?() -> :ok
      not is_nil(causer_id) and to_string(causer_id) == to_string(user_id) -> :ok
      true -> store(user_id, type, ticket, extra)
    end
  end

  defp store(user_id, type, ticket, extra) do
    data =
      Map.merge(
        %{"ticket_id" => ticket.id, "reference" => ticket.reference},
        Map.new(extra, fn {key, value} -> {to_string(key), value} end)
      )

    notification =
      Escalated.repo().insert!(%AgentNotification{
        user_id: to_string(user_id),
        type: type,
        data: data,
        inserted_at: now()
      })

    recipient = TicketVisibility.load_user(user_id)
    [item] = TicketVisibility.with_user(recipient, fn -> present([notification]) end)
    Broadcasting.notification_created(user_id, item)
  end

  @doc "The agent's unread notification count."
  def unread_count(user) do
    user
    |> notifications_query()
    |> where([n], is_nil(n.read_at))
    |> Escalated.repo().aggregate(:count)
  end

  @doc """
  A page of the agent's notifications, newest first: `{items, meta}`.
  `per_page` is clamped to 1..50 (default 20); `unread: true` keeps unread ones.
  """
  def page(user, params) do
    per_page = params |> Map.get("per_page") |> int(20) |> min(50) |> max(1)
    page = params |> Map.get("page") |> int(1) |> max(1)

    query =
      if params["unread"] in ["1", "true", 1, true],
        do: where(notifications_query(user), [n], is_nil(n.read_at)),
        else: notifications_query(user)

    repo = Escalated.repo()
    total = repo.aggregate(query, :count)

    rows =
      query
      |> order_by([n], desc: n.inserted_at, desc: n.id)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> repo.all()

    meta = %{
      current_page: page,
      last_page: max(1, div(total + per_page - 1, per_page)),
      per_page: per_page,
      total: total
    }

    {present(rows), meta}
  end

  @doc "Marks one of the agent's notifications read: `:ok` or `:not_found`."
  def read(user, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        {count, _} =
          user
          |> notifications_query()
          |> where([n], n.id == ^uuid)
          |> Escalated.repo().update_all(set: [read_at: now()])

        if count == 0, do: :not_found, else: :ok

      :error ->
        :not_found
    end
  end

  @doc "Marks every notification of the agent's read."
  def read_all(user) do
    user
    |> notifications_query()
    |> where([n], is_nil(n.read_at))
    |> Escalated.repo().update_all(set: [read_at: now()])

    :ok
  end

  defp notifications_query(user),
    do: from(n in AgentNotification, where: n.user_id == ^to_string(user.id))

  @doc """
  Feed items for `notifications`, as the current ticket-visibility actor sees
  them: one ticket query for the page. A notification about a ticket the
  agent can no longer view is redacted.
  """
  def present(notifications) do
    ids =
      notifications
      |> Enum.map(&ticket_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    tickets =
      if ids == [],
        do: %{},
        else:
          from(t in Ticket, where: t.id in ^ids)
          |> Escalated.repo().all()
          |> Map.new(&{&1.id, &1})

    Enum.map(notifications, &item(&1, tickets))
  end

  defp item(notification, tickets) do
    data = notification.data || %{}
    type = if Map.has_key?(@titles, notification.type), do: notification.type, else: "generic"

    case ticket_id(notification) do
      nil ->
        shape(notification, type, title(type, data["reference"], data), nil, nil)

      id ->
        case Map.get(tickets, id) do
          nil -> shape(notification, type, @unavailable, nil, nil)
          ticket -> shape(notification, type, title(type, ticket.reference, data), ticket)
        end
    end
  end

  defp shape(notification, type, title, %Ticket{} = ticket) do
    notification
    |> shape(type, title, ticket.subject, %{
      id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject
    })
    |> Map.put(
      :url,
      "#{Escalated.config(:route_prefix, "/support")}/agent/tickets/#{ticket.reference}"
    )
  end

  defp shape(notification, type, title, body, ticket) do
    %{
      id: notification.id,
      type: type,
      title: title,
      body: body,
      ticket: ticket,
      url: nil,
      created_at: notification.inserted_at,
      read_at: notification.read_at
    }
  end

  defp title(type, reference, data) do
    Regex.replace(~r/%\{(\w+)\}/, Map.fetch!(@titles, type), fn _, key ->
      case key do
        "reference" -> to_string(reference || "")
        "name" -> to_string(data["mentioned_by"] || "")
      end
    end)
  end

  defp ticket_id(%AgentNotification{data: %{"ticket_id" => id}}) when is_integer(id), do: id

  defp ticket_id(%AgentNotification{data: %{"ticket_id" => id}}) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp ticket_id(_), do: nil

  # --- Helpers ------------------------------------------------------------

  defp int(value, _default) when is_integer(value), do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp int(_value, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
