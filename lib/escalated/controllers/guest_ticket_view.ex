defmodule Escalated.Controllers.GuestTicketView do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.{AgentProfile, Attachment, Department, Reply}
  alias Escalated.Services.GuestAccess

  # English labels and badge colours for the guest-facing status, the same
  # as the Laravel reference's TicketStatus enum.
  @statuses %{
    "open" => {"Open", "#3B82F6"},
    "in_progress" => {"In Progress", "#8B5CF6"},
    "waiting_on_customer" => {"Waiting on Customer", "#F59E0B"},
    "waiting_on_agent" => {"Waiting on Agent", "#F97316"},
    "escalated" => {"Escalated", "#EF4444"},
    "resolved" => {"Resolved", "#10B981"},
    "closed" => {"Closed", "#6B7280"},
    "reopened" => {"Reopened", "#3B82F6"},
    "snoozed" => {"Snoozed", "#6B7280"},
    "live" => {"Live", "#06B6D4"}
  }

  def summary(ticket),
    do: %{
      "reference" => ticket.reference,
      "subject" => ticket.subject,
      "status" => ticket.status,
      "priority" => ticket.priority,
      "created_at" => ticket.inserted_at
    }

  def correspondence(ticket, token, grant) do
    replies =
      Escalated.repo().all(
        from(r in Reply,
          where: r.ticket_id == ^ticket.id and r.is_internal == false,
          order_by: [desc: r.inserted_at, desc: r.id],
          limit: 100
        )
      )
      |> Enum.reverse()

    reply_ids = Enum.map(replies, & &1.id)
    agents = replies |> Enum.map(& &1.author_id) |> agent_names()

    attachments =
      Escalated.repo().all(
        from(a in Attachment,
          where:
            (a.ticket_id == ^ticket.id and is_nil(a.reply_id)) or
              (a.reply_id in ^reply_ids and (is_nil(a.ticket_id) or a.ticket_id == ^ticket.id)),
          order_by: [asc: a.id],
          limit: 100
        )
      )
      |> Enum.group_by(& &1.reply_id)

    {label, color} = status(ticket.status)

    summary(ticket)
    |> Map.put("status_label", label)
    |> Map.put("status_color", color)
    |> Map.put("department", department_name(ticket.department_id))
    |> Map.put("description", ticket.description)
    |> Map.put("attachments", files(attachments[nil] || [], token, grant))
    |> Map.put(
      "replies",
      Enum.map(replies, fn reply ->
        %{
          body: reply.body,
          author: author_name(reply, ticket, agents),
          is_agent: agent?(reply),
          created_at: reply.inserted_at,
          attachments: files(attachments[reply.id] || [], token, grant)
        }
      end)
    )
  end

  @doc "The guest-facing label and badge colour of a ticket status."
  def status(status), do: Map.get(@statuses, status, {humanize(status), "#6B7280"})

  @doc """
  Whether a public reply was written by staff. Guest replies, and replies the
  system writes for the guest, have no author.
  """
  def agent?(%Reply{author_id: author_id}), do: not is_nil(author_id)

  @doc """
  The name shown to the guest for a reply's author: the agent's display name
  (or their name in the host's user schema), else "Support"; the guest's own
  name for their replies. `agents` comes from `agent_names/1`.
  """
  def author_name(%Reply{} = reply, ticket, agents) do
    if agent?(reply),
      do: Map.get(agents, reply.author_id) || "Support",
      else: ticket.guest_name || "You"
  end

  @doc "Display names of the given agents, by user id. Agents with no name are left out."
  def agent_names(author_ids) do
    ids = author_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      %{}
    else
      profiles =
        Escalated.repo().all(
          from(p in AgentProfile, where: p.user_id in ^ids, select: {p.user_id, p.display_name})
        )
        |> Enum.reject(fn {_, name} -> blank?(name) end)
        |> Map.new()

      ids
      |> Enum.reject(&Map.has_key?(profiles, &1))
      |> user_names()
      |> Map.merge(profiles)
    end
  end

  defp user_names([]), do: %{}

  defp user_names(ids) do
    case Escalated.config(:user_schema) do
      nil ->
        %{}

      schema ->
        Escalated.user_repo().all(from(u in schema, where: u.id in ^ids))
        |> Enum.map(&{&1.id, user_name(&1)})
        |> Enum.reject(fn {_, name} -> blank?(name) end)
        |> Map.new()
    end
  end

  defp user_name(user) do
    if function_exported?(user.__struct__, :name, 1),
      do: user.__struct__.name(user),
      else: Map.get(user, :name)
  end

  defp department_name(nil), do: nil

  defp department_name(id) do
    case Escalated.repo().get(Department, id) do
      %Department{name: name} -> name
      nil -> nil
    end
  end

  defp humanize(nil), do: nil

  defp humanize(status),
    do: status |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""

  defp files(attachments, token, grant),
    do:
      Enum.map(attachments, fn attachment ->
        %{
          filename: attachment.original_filename,
          mime_type: attachment.mime_type,
          size: attachment.size,
          url: GuestAccess.attachment_url(attachment, token, grant)
        }
      end)
end
