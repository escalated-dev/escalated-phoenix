defmodule Escalated.Rendering.TicketPresenter do
  @moduledoc """
  Tickets in the shapes the shared Vue pages read, built field by field.

    * `rows/1` -- queue rows for `TicketList` and the agent dashboard:
      `requester`, `assignee`, `department`, `tags`, `latest_reply` and the
      SLA fields alongside the ticket's own columns.
    * `staff_detail/1` -- the agent and admin ticket page: a row plus the
      thread (`replies`, newest first, internal notes included), the
      `pinned_notes`, `activities`, `satisfaction_rating`, `sla_policy` and the
      chat and related-ticket fields.
    * `customer_row/1`, `customer_detail/1` -- the requester's view, after
      escalated-laravel's `CustomerTicketPayload`: no internal notes, staff by
      display name only, and no assignee, metadata or guest credentials.
  """
  import Ecto.Query

  alias Escalated.Rendering.UserDirectory

  alias Escalated.Schemas.{
    Attachment,
    Reply,
    SatisfactionRating,
    Tag,
    Ticket,
    TicketActivity,
    TicketTag
  }

  alias Escalated.Serializers.TicketSerializer

  @activity_limit 20

  # ---------------------------------------------------------------------------
  # Staff
  # ---------------------------------------------------------------------------

  @doc "Queue rows for a list of tickets."
  def rows(tickets) do
    tickets = Escalated.repo().preload(tickets, :department)
    directory = UserDirectory.lookup(Enum.map(tickets, & &1.assigned_to))
    tags = tags_by_ticket(Enum.map(tickets, & &1.id))
    Enum.map(tickets, &row(&1, directory, Map.get(tags, &1.id, [])))
  end

  @doc "One queue row. `directory` is a `UserDirectory.lookup/1` result."
  def row(%Ticket{} = ticket, directory, tags \\ nil) do
    ticket = Escalated.repo().preload(ticket, :department)
    tags = tags || Map.get(tags_by_ticket([ticket.id]), ticket.id, [])
    computed = TicketSerializer.computed_fields(ticket)

    %{
      id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject,
      status: ticket.status,
      priority: ticket.priority,
      ticket_type: ticket.ticket_type,
      channel: ticket.channel,
      assigned_to: ticket.assigned_to,
      department_id: ticket.department_id,
      department: department(ticket),
      requester: %{name: computed.requester_name, email: computed.requester_email},
      assignee: UserDirectory.get(directory, ticket.assigned_to),
      tags: Enum.map(tags, &%{id: &1.id, name: &1.name, color: &1.color}),
      latest_reply: latest_reply(computed),
      sla_breached: ticket.sla_breached,
      first_response_due_at: iso(ticket.sla_first_response_due_at),
      resolution_due_at: iso(ticket.sla_resolution_due_at),
      sla_first_response_breached:
        breached?(ticket.sla_first_response_due_at, ticket.first_response_at),
      sla_resolution_breached:
        breached?(ticket.sla_resolution_due_at, ticket.resolved_at || ticket.closed_at),
      snoozed_until: iso(ticket.snoozed_until),
      created_at: iso(ticket.inserted_at),
      updated_at: iso(ticket.updated_at)
    }
    |> Map.merge(computed)
  end

  @doc "The ticket for `Agent/TicketShow` and `Admin/Tickets/Show`."
  def staff_detail(%Ticket{} = ticket) do
    repo = Escalated.repo()
    ticket = repo.preload(ticket, [:department, :sla_policy])

    replies =
      from(r in Reply,
        where: r.ticket_id == ^ticket.id,
        order_by: [desc: r.inserted_at, desc: r.id],
        preload: :attachments
      )
      |> repo.all()

    activities =
      from(a in TicketActivity, where: a.ticket_id == ^ticket.id)
      |> TicketActivity.reverse_chronological()
      |> limit(@activity_limit)
      |> repo.all()

    directory =
      UserDirectory.lookup(
        [ticket.assigned_to] ++
          Enum.map(replies, & &1.author_id) ++ Enum.map(activities, & &1.causer_id)
      )

    pinned = Enum.filter(replies, &(&1.is_internal and &1.is_pinned))

    ticket
    |> row(directory)
    |> Map.merge(%{
      description: ticket.description,
      metadata: ticket.metadata,
      sla_policy_id: ticket.sla_policy_id,
      sla_policy: ticket.sla_policy && %{id: ticket.sla_policy.id, name: ticket.sla_policy.name},
      sla_first_response_due_at: iso(ticket.sla_first_response_due_at),
      sla_resolution_due_at: iso(ticket.sla_resolution_due_at),
      first_response_at: iso(ticket.first_response_at),
      resolved_at: iso(ticket.resolved_at),
      closed_at: iso(ticket.closed_at),
      attachments: ticket_attachments(ticket),
      replies: Enum.map(replies, &staff_reply(&1, directory)),
      pinned_notes: Enum.map(pinned, &staff_reply(&1, directory)),
      activities: Enum.map(activities, &activity(&1, directory)),
      satisfaction_rating: satisfaction_rating(ticket)
    })
    |> Map.merge(TicketSerializer.detail_fields(ticket))
  end

  defp staff_reply(reply, directory) do
    %{
      id: reply.id,
      body: reply.body,
      is_internal: reply.is_internal,
      is_internal_note: reply.is_internal,
      is_system: reply.is_system,
      is_pinned: reply.is_pinned,
      author_id: reply.author_id,
      author: UserDirectory.get(directory, reply.author_id),
      attachments: Enum.map(reply.attachments, &attachment/1),
      created_at: iso(reply.inserted_at)
    }
  end

  defp activity(a, directory) do
    %{
      id: a.id,
      type: a.action,
      action: a.action,
      description: a.description || humanize(a.action),
      causer_id: a.causer_id,
      causer: UserDirectory.get(directory, a.causer_id),
      properties: a.details,
      details: a.details,
      created_at: iso(a.inserted_at),
      created_at_human: TicketSerializer.human_time(a.inserted_at)
    }
  end

  # ---------------------------------------------------------------------------
  # Customer
  # ---------------------------------------------------------------------------

  @doc "A row of the requester's own queue."
  def customer_row(%Ticket{} = ticket) do
    ticket = Escalated.repo().preload(ticket, :department)
    computed = TicketSerializer.computed_fields(ticket, public: true)

    %{
      id: ticket.id,
      reference: ticket.reference,
      subject: ticket.subject,
      status: ticket.status,
      priority: ticket.priority,
      ticket_type: ticket.ticket_type,
      department: ticket.department && %{name: ticket.department.name},
      requester: %{name: computed.requester_name, email: computed.requester_email},
      latest_reply: latest_reply(computed),
      last_reply_at: computed.last_reply_at,
      created_at: iso(ticket.inserted_at),
      updated_at: iso(ticket.updated_at)
    }
  end

  @doc """
  The ticket for `Customer/Show` (and, with the guest-link expiry, for
  `Guest/Show`): Laravel's `CustomerTicketPayload::customerWeb/1`.
  """
  def customer_detail(%Ticket{} = ticket, opts \\ []) do
    url = Keyword.get(opts, :attachment_url, &Attachment.url/1)
    repo = Escalated.repo()
    ticket = repo.preload(ticket, :department)

    replies =
      from(r in Reply,
        where: r.ticket_id == ^ticket.id and r.is_internal == false,
        order_by: [desc: r.inserted_at, desc: r.id],
        preload: :attachments
      )
      |> repo.all()

    directory = UserDirectory.lookup(Enum.map(replies, & &1.author_id))
    computed = TicketSerializer.computed_fields(ticket, public: true)

    %{
      reference: ticket.reference,
      subject: ticket.subject,
      description: ticket.description || "",
      status: ticket.status,
      priority: ticket.priority,
      channel: ticket.channel,
      department: ticket.department && %{name: ticket.department.name},
      attachments: ticket_attachments(ticket, url),
      replies:
        Enum.map(replies, fn reply ->
          %{
            id: reply.id,
            body: reply.body,
            is_internal_note: false,
            is_pinned: reply.is_pinned,
            author: %{name: customer_author_name(ticket, reply, directory, computed)},
            attachments: Enum.map(reply.attachments, &attachment(&1, url)),
            created_at: iso(reply.inserted_at)
          }
        end),
      satisfaction_rating: satisfaction_rating(ticket),
      resolved_at: iso(ticket.resolved_at),
      closed_at: iso(ticket.closed_at),
      created_at: iso(ticket.inserted_at),
      updated_at: iso(ticket.updated_at)
    }
  end

  # The requester's own replies carry their name; anyone else is staff, shown
  # by display name, or "Support".
  defp customer_author_name(ticket, reply, directory, computed) do
    cond do
      is_nil(reply.author_id) ->
        computed.requester_name || "Guest"

      to_string(reply.author_id) == to_string(ticket.requester_id) ->
        UserDirectory.name(directory, reply.author_id) || computed.requester_name

      true ->
        UserDirectory.name(directory, reply.author_id) || "Support"
    end
  end

  # ---------------------------------------------------------------------------
  # Shared
  # ---------------------------------------------------------------------------

  @doc "An attachment as the pages' AttachmentList reads it."
  def attachment(%Attachment{} = a, url \\ &Attachment.url/1) do
    %{
      id: a.id,
      original_filename: a.original_filename,
      mime_type: a.mime_type,
      size: a.size,
      url: url.(a),
      created_at: iso(a.inserted_at)
    }
  end

  defp ticket_attachments(ticket, url \\ &Attachment.url/1) do
    from(a in Attachment, where: a.ticket_id == ^ticket.id and is_nil(a.reply_id))
    |> Escalated.repo().all()
    |> Enum.map(&attachment(&1, url))
  end

  defp satisfaction_rating(ticket) do
    from(s in SatisfactionRating, where: s.ticket_id == ^ticket.id, limit: 1)
    |> Escalated.repo().one()
    |> case do
      nil -> nil
      rating -> %{rating: rating.rating, comment: rating.comment}
    end
  end

  # Tags in two plain queries: the ticket-visibility query scope refuses an
  # association preload of the many-to-many, and joins through it.
  defp tags_by_ticket([]), do: %{}

  defp tags_by_ticket(ids) do
    repo = Escalated.repo()

    links =
      from(tt in TicketTag, where: tt.ticket_id in ^ids, select: {tt.ticket_id, tt.tag_id})
      |> repo.all()

    tags =
      case Enum.map(links, &elem(&1, 1)) |> Enum.uniq() do
        [] -> %{}
        tag_ids -> from(t in Tag, where: t.id in ^tag_ids) |> repo.all() |> Map.new(&{&1.id, &1})
      end

    links
    |> Enum.flat_map(fn {ticket_id, tag_id} ->
      case Map.fetch(tags, tag_id) do
        {:ok, tag} -> [{ticket_id, tag}]
        :error -> []
      end
    end)
    |> Enum.sort_by(fn {_ticket_id, tag} -> tag.name end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp department(%{department: %{id: id, name: name}}), do: %{id: id, name: name}
  defp department(_), do: nil

  defp latest_reply(%{last_reply_at: nil}), do: nil

  defp latest_reply(%{last_reply_at: at, last_reply_author: author}),
    do: %{created_at: at, author: %{name: author}}

  defp breached?(nil, _met_at), do: false

  defp breached?(due, nil), do: DateTime.compare(DateTime.utc_now(), due) == :gt
  defp breached?(due, met_at), do: DateTime.compare(met_at, due) == :gt

  defp humanize(nil), do: nil
  defp humanize(action), do: action |> String.replace("_", " ") |> String.capitalize()

  defp iso(nil), do: nil
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
