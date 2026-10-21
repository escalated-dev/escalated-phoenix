defmodule Escalated.Notifications do
  @moduledoc """
  Outbound ticket notification emails, sent through the host's mailer.

  `Escalated.Events.emit/2` hands every event here. The recipients follow
  escalated-laravel's notification listeners:

    * `ticket.created`: the requester (the thread's first message) and the
      assignee, if the ticket was created assigned.
    * `reply.created` (public replies only): the requester, unless they wrote
      it; the assignee, unless they wrote it; and every follower except the
      author, the requester and the assignee.
    * `ticket.assigned`: the new assignee.
    * `ticket.status_changed`: the requester and the followers, except whoever
      changed the status.
    * `ticket.escalated`: the assignee.
    * `sla.breached`: the assignee.

  Internal notes, live chat messages and the other events email nobody, and
  nobody is emailed about their own action.

  Agents (the assignee and followers) are host users, looked up through
  `:user_schema` on `Escalated.user_repo/0` and filtered with
  `Escalated.TicketVisibility.recipients/2`. The requester is the host user for
  a user ticket, and the guest address (or the ticket's contact) for a guest
  ticket.

  Each message carries the threading headers of `Escalated.Emails.TicketEmail`
  (`Message-ID`, `In-Reply-To`, `References`) and, when
  `:email_inbound_secret` is set, a signed `Reply-To`, so replies by email
  thread back onto the ticket.

  ## Configuration

  Nothing is sent until the host names how to send it:

      # a Swoosh mailer (`use Swoosh.Mailer`); Escalated calls deliver/1
      config :escalated, mailer: MyApp.Mailer

      # or any function, given a map with :to, :from, :subject, :headers,
      # :reply_to, :html_body and :text_body
      config :escalated, notification_delivery: &MyApp.SupportMail.deliver/1

  Email is sent only while `:notification_channels` includes `:email` (the
  default). Delivery runs in a separate process so a slow mail server never
  holds up the request; `config :escalated, notification_sync: true` sends
  inline instead. A failing mailer is logged and never breaks the ticket
  operation.
  """

  require Logger

  alias Escalated.Emails.TicketEmail
  alias Escalated.Schemas.{Contact, Ticket}
  alias Escalated.Services.Followers

  @swoosh_email Swoosh.Email

  @doc "Send the notification emails for `event`. Always returns `:ok`."
  def notify(event, context) when is_binary(event) and is_map(context) do
    case delivery() do
      nil ->
        :ok

      delivery ->
        if email_channel?() do
          event
          |> messages(context)
          |> Enum.each(&deliver(delivery, &1))
        end

        :ok
    end
  rescue
    error ->
      Logger.warning("Escalated notification for #{event} failed: #{Exception.message(error)}")
      :ok
  end

  @doc "True when emails will be sent: a mailer is configured and :email is a channel."
  def enabled?, do: not is_nil(delivery()) and email_channel?()

  # --- Who gets what ---

  defp messages("ticket.created", %{ticket: %Ticket{} = ticket}) do
    subject = "[#{ticket.reference}] New Ticket: #{ticket.subject}"

    [requester_address(ticket) | agent_addresses(ticket, [ticket.assigned_to])]
    |> addresses()
    |> Enum.map(&TicketEmail.new_ticket_email(ticket, &1, subject: subject))
  end

  defp messages("reply.created", %{ticket: %Ticket{} = ticket, reply: reply} = context) do
    if Map.get(context, :notify, true) == false or reply.is_internal do
      []
    else
      author = reply.author_id && to_string(reply.author_id)

      requester =
        if requester_wrote?(ticket, reply, context), do: [], else: [requester_address(ticket)]

      assignee = if same_id?(ticket.assigned_to, author), do: [], else: [ticket.assigned_to]

      followers =
        ticket.id
        |> Followers.follower_user_ids(author)
        |> Enum.reject(
          &(same_id?(&1, user_requester_id(ticket)) or same_id?(&1, ticket.assigned_to))
        )

      (requester ++ agent_addresses(ticket, assignee ++ followers))
      |> addresses()
      |> Enum.map(&TicketEmail.reply_email(ticket, reply, &1))
    end
  end

  defp messages("ticket.assigned", %{ticket: %Ticket{} = ticket, agent_id: agent_id}) do
    notice(
      ticket,
      agent_addresses(ticket, [agent_id]),
      "[#{ticket.reference}] Ticket Assigned to You",
      [
        "A ticket has been assigned to you.",
        "Subject: #{ticket.subject}",
        "Priority: #{label(ticket.priority)}"
      ]
    )
  end

  defp messages("ticket.status_changed", %{ticket: %Ticket{} = ticket} = context) do
    actor = Map.get(context, :actor_id)

    requester =
      if same_id?(user_requester_id(ticket), actor), do: [], else: [requester_address(ticket)]

    followers =
      ticket.id
      |> Followers.follower_user_ids(actor)
      |> Enum.reject(&same_id?(&1, user_requester_id(ticket)))

    from = Map.get(context, :from)

    notice(
      ticket,
      requester ++ agent_addresses(ticket, followers),
      "[#{ticket.reference}] Status Updated: #{label(ticket.status)}",
      [
        "The status of your ticket has been updated.",
        if(from, do: "From: #{label(from)}"),
        "To: #{label(ticket.status)}"
      ]
    )
  end

  defp messages("ticket.escalated", %{ticket: %Ticket{} = ticket}) do
    subject = "[Escalated] [#{ticket.reference}] #{ticket.subject}"

    notice(ticket, agent_addresses(ticket, [ticket.assigned_to]), subject, [
      "A ticket has been escalated.",
      "Subject: #{ticket.subject}",
      "Priority: #{label(ticket.priority)}"
    ])
  end

  defp messages("sla.breached", %{ticket: %Ticket{} = ticket} = context) do
    type = sla_type(Map.get(context, :breach_type))

    subject = "[SLA Breach] [#{ticket.reference}] #{type} SLA Breached"

    notice(ticket, agent_addresses(ticket, [ticket.assigned_to]), subject, [
      "An SLA has been breached on ticket #{ticket.reference}.",
      "Type: #{type} SLA",
      "Subject: #{ticket.subject}",
      "Priority: #{label(ticket.priority)}"
    ])
  end

  defp messages(_event, _context), do: []

  defp notice(ticket, recipients, subject, lines) do
    lines = Enum.reject(lines, &is_nil/1)

    recipients
    |> addresses()
    |> Enum.map(&TicketEmail.notice_email(ticket, &1, subject, lines))
  end

  # A reply was written by the requester when its author is the requesting
  # user, or when it has no author and is not the system's own (a guest
  # replying through the widget, the guest page or email).
  defp requester_wrote?(ticket, reply, context) do
    cond do
      Map.get(context, :author) == :system -> false
      reply.is_system -> false
      is_nil(reply.author_id) -> true
      true -> same_id?(user_requester_id(ticket), reply.author_id)
    end
  end

  # --- Addresses ---

  defp user_requester_id(%Ticket{requester_type: "guest"}), do: nil
  defp user_requester_id(%Ticket{requester_id: id}), do: id

  defp requester_address(%Ticket{} = ticket) do
    case user_requester_id(ticket) do
      nil -> present(ticket.guest_email) || contact_email(ticket)
      id -> user_email(id) || present(ticket.guest_email)
    end
  end

  defp agent_addresses(ticket, ids) do
    ids = ids |> Enum.reject(&is_nil/1) |> Enum.map(&to_string/1) |> Enum.uniq()

    ticket
    |> Escalated.TicketVisibility.recipients(ids)
    |> Enum.map(&user_email/1)
  end

  defp user_email(id) do
    case Escalated.config(:user_schema) do
      nil ->
        nil

      schema ->
        case Escalated.user_repo().get(schema, id) do
          %{email: email} -> present(email)
          _ -> nil
        end
    end
  rescue
    Ecto.Query.CastError -> nil
  end

  defp contact_email(%Ticket{contact_id: nil}), do: nil

  defp contact_email(%Ticket{contact_id: id}) do
    case Escalated.repo().get(Contact, id) do
      %Contact{email: email} -> present(email)
      _ -> nil
    end
  end

  # One message per address, compared case-insensitively.
  defp addresses(list) do
    list
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp same_id?(nil, _), do: false
  defp same_id?(_, nil), do: false
  defp same_id?(a, b), do: to_string(a) == to_string(b)

  defp label(nil), do: ""

  defp label(value) do
    value
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp sla_type(type) when type in [:resolution, "resolution"], do: "Resolution"
  defp sla_type(_), do: "First Response"

  # --- Sending ---

  defp email_channel? do
    :notification_channels
    |> Escalated.config([:email])
    |> List.wrap()
    |> Enum.any?(&(to_string(&1) in ["email", "mail"]))
  end

  defp delivery do
    fun = Escalated.config(:notification_delivery)
    mailer = Escalated.config(:mailer)

    cond do
      is_function(fun, 1) -> {:fun, fun}
      is_atom(mailer) and not is_nil(mailer) -> {:mailer, mailer}
      true -> nil
    end
  end

  defp deliver(delivery, message) do
    message = split_reply_to(message)

    if Escalated.config(:notification_sync, false) do
      send_one(delivery, message)
    else
      Task.start(fn -> send_one(delivery, message) end)
    end
  end

  defp send_one({:fun, fun}, message), do: guarded(message, fn -> fun.(message) end)

  defp send_one({:mailer, mailer}, message),
    do: guarded(message, fn -> mailer.deliver(swoosh_email(message)) end)

  defp guarded(message, fun) do
    case fun.() do
      {:error, reason} -> log_failure(message, inspect(reason))
      _ -> :ok
    end
  rescue
    error -> log_failure(message, Exception.message(error))
  catch
    kind, reason -> log_failure(message, "#{kind}: #{inspect(reason)}")
  end

  defp log_failure(message, reason) do
    Logger.warning("Escalated notification email \"#{message.subject}\" was not sent: #{reason}")
  end

  # Mailers set Reply-To from its own field, not a raw header.
  defp split_reply_to(message) do
    {reply_to, headers} = Map.pop(message.headers, "Reply-To")
    message |> Map.put(:headers, headers) |> Map.put(:reply_to, reply_to)
  end

  # Built at runtime: Swoosh is the host's dependency, not this package's.
  defp swoosh_email(message) do
    struct(@swoosh_email, %{
      to: [{"", message.to}],
      from: message.from,
      subject: message.subject,
      headers: message.headers,
      reply_to: message.reply_to && {"", message.reply_to},
      html_body: message.html_body,
      text_body: message.text_body
    })
  end
end
