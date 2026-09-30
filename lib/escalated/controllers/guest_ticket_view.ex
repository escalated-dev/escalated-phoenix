defmodule Escalated.Controllers.GuestTicketView do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Schemas.{Attachment, Reply}
  alias Escalated.Services.GuestAccess

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

    summary(ticket)
    |> Map.put("description", ticket.description)
    |> Map.put("attachments", files(attachments[nil] || [], token, grant))
    |> Map.put(
      "replies",
      Enum.map(replies, fn reply ->
        %{
          body: reply.body,
          created_at: reply.inserted_at,
          attachments: files(attachments[reply.id] || [], token, grant)
        }
      end)
    )
  end

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
