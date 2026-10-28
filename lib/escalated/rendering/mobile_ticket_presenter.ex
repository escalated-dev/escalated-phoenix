defmodule Escalated.Rendering.MobileTicketPresenter do
  @moduledoc """
  The requester-facing ticket object of the mobile guest API, as fixed by the
  shared contract (`domain-model/mobile-guest-api.md` in
  escalated-developer-context; escalated-laravel's `MobileTicketResource`).

  Allow-listed: the ticket schema is never serialized. Staff appear by display
  name only, `metadata` is always an empty object, and internal notes,
  `chat_metadata`, staff ids and emails never appear.
  """
  import Ecto.Query

  alias Escalated.Controllers.GuestTicketView
  alias Escalated.Schemas.{Attachment, Department, GuestGrant, Reply, Ticket}
  alias Escalated.Services.GuestAccess

  # The newest public replies a guest is shown, as on the other guest surfaces.
  @reply_limit 100

  @doc """
  The mobile ticket object. `token` is the grant the guest used (or was just
  issued) and `expires_at` its expiry; `replies: true` fills `replies`, public
  replies only, newest first, with attachment links bound to the grant.
  """
  def ticket(%Ticket{} = ticket, token, expires_at, opts \\ []) do
    grant = Keyword.get(opts, :grant)

    replies =
      if Keyword.get(opts, :replies, false) and grant,
        do: replies(ticket, token, grant),
        else: []

    {status_label, _color} = GuestTicketView.status(ticket.status)

    %{
      id: ticket.id,
      reference: ticket.reference,
      guest_access_token: token,
      guest_access_expires_at: if(token, do: iso(expires_at)),
      subject: ticket.subject,
      description: ticket.description || "",
      status: %{value: ticket.status, label: status_label},
      priority: %{value: ticket.priority, label: label(ticket.priority)},
      channel: ticket.channel,
      metadata: %{},
      requester: %{name: present(ticket.guest_name) || "Guest", email: ticket.guest_email},
      assignee: assignee(ticket.assigned_to),
      department: department(ticket.department_id),
      tags: [],
      replies: replies,
      activities: [],
      sla: %{
        first_response_due_at: iso(ticket.sla_first_response_due_at),
        first_response_at: iso(ticket.first_response_at),
        first_response_breached:
          breached?(ticket.sla_first_response_due_at, ticket.first_response_at),
        resolution_due_at: iso(ticket.sla_resolution_due_at),
        resolution_breached:
          breached?(ticket.sla_resolution_due_at, ticket.resolved_at || ticket.closed_at)
      },
      is_following: false,
      followers_count: 0,
      resolved_at: iso(ticket.resolved_at),
      closed_at: iso(ticket.closed_at),
      created_at: iso(ticket.inserted_at),
      updated_at: iso(ticket.updated_at)
    }
  end

  defp replies(ticket, token, %GuestGrant{} = grant) do
    repo = Escalated.repo()

    replies =
      repo.all(
        from(r in Reply,
          where: r.ticket_id == ^ticket.id and r.is_internal == false,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: @reply_limit
        )
      )

    ids = Enum.map(replies, & &1.id)
    agents = replies |> Enum.map(& &1.author_id) |> GuestTicketView.agent_names()

    # Only files on these public replies of this ticket: never an internal
    # note's.
    files =
      repo.all(
        from(a in Attachment,
          where: a.reply_id in ^ids and (is_nil(a.ticket_id) or a.ticket_id == ^ticket.id),
          order_by: [asc: a.id]
        )
      )
      |> Enum.group_by(& &1.reply_id)

    Enum.map(replies, fn reply ->
      %{
        id: reply.id,
        body: reply.body,
        is_internal_note: false,
        is_pinned: reply.is_pinned == true,
        author: author(reply, ticket, agents),
        attachments:
          Enum.map(files[reply.id] || [], fn file ->
            %{
              id: file.id,
              filename: file.original_filename,
              mime_type: file.mime_type,
              size: file.size,
              url: GuestAccess.attachment_url(file, token, grant)
            }
          end),
        created_at: iso(reply.inserted_at)
      }
    end)
  end

  defp author(%Reply{author_id: nil}, ticket, _agents),
    do: %{id: 0, name: present(ticket.guest_name) || "Guest", email: ticket.guest_email}

  defp author(%Reply{author_id: id}, _ticket, agents),
    do: %{id: 0, name: Map.get(agents, id) || "Support", email: ""}

  defp assignee(nil), do: nil

  defp assignee(user_id),
    do: %{
      id: 0,
      name: Map.get(GuestTicketView.agent_names([user_id]), user_id) || "Support",
      email: ""
    }

  defp department(nil), do: nil

  defp department(id) do
    case Escalated.repo().get(Department, id) do
      %Department{name: name} -> %{id: id, name: name}
      nil -> nil
    end
  end

  defp label(nil), do: nil
  defp label(value), do: value |> to_string() |> String.capitalize()

  defp breached?(nil, _met_at), do: false
  defp breached?(due, nil), do: DateTime.compare(DateTime.utc_now(), due) == :gt
  defp breached?(due, met_at), do: DateTime.compare(met_at, due) == :gt

  defp present(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp present(_), do: nil

  defp iso(nil), do: nil
  defp iso(value) when is_binary(value), do: value
  defp iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp iso(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"
end
