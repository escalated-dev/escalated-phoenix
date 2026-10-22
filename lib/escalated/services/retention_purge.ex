defmodule Escalated.Services.RetentionPurge do
  @moduledoc """
  Applies the admin data-retention settings (`retention_closed_tickets`,
  `retention_attachments`, `retention_audit_logs`). Run by
  `mix escalated.purge_expired`; `preview/0` is the count the data-retention
  page shows. Mirrors escalated-laravel's `escalated:purge-expired`.

  Every setting defaults to `"never"`, and a `"never"` setting touches
  nothing, so an install that has not opted in loses no data.

  Closed tickets are deleted outright. Laravel soft-deletes them first and
  removes them for good 30 days later; the Phoenix ticket schema has no
  `deleted_at`, so there is no grace period here. Their replies, activities,
  attachments (and stored files), tags, followers, ratings, links, side
  conversations, workflow logs, delayed actions, guest grants and custom field
  values go with them. A ticket that was merged into a purged one is kept and
  its `merged_into_id` cleared.
  """
  import Ecto.Query

  alias Escalated.Schemas.{
    Attachment,
    AuditLog,
    ChatSession,
    CustomFieldValue,
    DelayedAction,
    GuestGrant,
    Mention,
    Reply,
    SatisfactionRating,
    SideConversation,
    SideConversationReply,
    Ticket,
    TicketActivity,
    TicketFollower,
    TicketLink,
    TicketSubject,
    TicketTag,
    WorkflowLog
  }

  alias Escalated.Services.SettingsService
  alias Escalated.Support.Retention

  @batch 500

  @type counts :: %{
          tickets: non_neg_integer,
          attachments: non_neg_integer,
          audit_logs: non_neg_integer
        }

  @doc "How many records a run would delete now. Never raises: zeros on failure."
  @spec preview() :: counts
  def preview do
    run(dry_run: true)
  rescue
    _ -> %{tickets: 0, attachments: 0, audit_logs: 0}
  end

  @doc """
  Deletes what the retention settings say has expired and returns the counts.
  With `dry_run: true` nothing is deleted and the counts are what would be.
  """
  @spec run(keyword) :: counts
  def run(opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)

    %{
      tickets: purge_tickets(cutoff("retention_closed_tickets"), dry_run?),
      attachments: purge_attachments(cutoff("retention_attachments"), dry_run?),
      audit_logs: purge_audit_logs(cutoff("retention_audit_logs"), dry_run?)
    }
  end

  defp cutoff(key), do: Retention.cutoff_for(SettingsService.get_or_default(key, "never"))

  defp expired_tickets(cutoff),
    do: from(t in Ticket, where: t.status == "closed" and t.closed_at < ^cutoff)

  defp purge_tickets(nil, _dry_run?), do: 0

  defp purge_tickets(cutoff, true), do: repo().aggregate(expired_tickets(cutoff), :count)

  defp purge_tickets(cutoff, false), do: purge_ticket_batches(cutoff, 0)

  defp purge_ticket_batches(cutoff, total) do
    ids =
      repo().all(from(t in expired_tickets(cutoff), select: t.id, order_by: t.id, limit: @batch))

    case ids do
      [] ->
        total

      ids ->
        {:ok, {count, files}} = repo().transaction(fn -> delete_tickets(ids) end)
        Enum.each(files, &remove_file/1)

        # A batch that deleted nothing would come back forever.
        if count == 0, do: total, else: purge_ticket_batches(cutoff, total + count)
    end
  end

  # Children first, so this works whether or not the database enforces the
  # cascades the migrations declare (several ticket references carry none).
  defp delete_tickets(ids) do
    reply_ids = repo().all(from(r in Reply, where: r.ticket_id in ^ids, select: r.id))

    attachments =
      from(a in Attachment, where: a.ticket_id in ^ids or a.reply_id in ^reply_ids)

    files = repo().all(attachments)
    repo().delete_all(attachments)
    repo().delete_all(from(m in Mention, where: m.reply_id in ^reply_ids))

    side_ids =
      repo().all(from(s in SideConversation, where: s.ticket_id in ^ids, select: s.id))

    repo().delete_all(
      from(r in SideConversationReply, where: r.side_conversation_id in ^side_ids)
    )

    for schema <- [
          SideConversation,
          Reply,
          TicketActivity,
          TicketTag,
          ChatSession,
          TicketSubject,
          GuestGrant,
          SatisfactionRating,
          TicketFollower,
          WorkflowLog,
          DelayedAction
        ] do
      repo().delete_all(from(r in schema, where: r.ticket_id in ^ids))
    end

    repo().delete_all(
      from(l in TicketLink, where: l.parent_ticket_id in ^ids or l.child_ticket_id in ^ids)
    )

    repo().delete_all(
      from(v in CustomFieldValue, where: v.entity_type == "ticket" and v.entity_id in ^ids)
    )

    repo().update_all(from(t in Ticket, where: t.merged_into_id in ^ids),
      set: [merged_into_id: nil]
    )

    {count, _} = repo().delete_all(from(t in Ticket, where: t.id in ^ids))
    {count, files}
  end

  defp purge_attachments(nil, _dry_run?), do: 0

  defp purge_attachments(cutoff, true),
    do: repo().aggregate(from(a in Attachment, where: a.inserted_at < ^cutoff), :count)

  defp purge_attachments(cutoff, false), do: purge_attachment_batches(cutoff, 0)

  defp purge_attachment_batches(cutoff, total) do
    files =
      repo().all(
        from(a in Attachment, where: a.inserted_at < ^cutoff, order_by: a.id, limit: @batch)
      )

    case files do
      [] ->
        total

      files ->
        ids = Enum.map(files, & &1.id)
        {count, _} = repo().delete_all(from(a in Attachment, where: a.id in ^ids))
        Enum.each(files, &remove_file/1)

        # A batch that deleted nothing would come back forever.
        if count == 0, do: total, else: purge_attachment_batches(cutoff, total + count)
    end
  end

  defp purge_audit_logs(nil, _dry_run?), do: 0

  defp purge_audit_logs(cutoff, dry_run?) do
    query = from(l in AuditLog, where: l.inserted_at < ^cutoff)

    if dry_run? do
      repo().aggregate(query, :count)
    else
      {count, _} = repo().delete_all(query)
      count
    end
  end

  # Only a locally stored file inside the upload directory, the same
  # containment the download route applies.
  defp remove_file(%Attachment{storage_backend: "local", storage_key: key})
       when is_binary(key) do
    root = Application.get_env(:escalated, :upload_dir, "priv/uploads") |> Path.expand()
    path = Path.expand(key, root)
    relative = Path.relative_to(path, root)

    if Path.type(relative) == :relative and ".." not in Path.split(relative) and path != root do
      _ = File.rm(path)
    end

    :ok
  end

  defp remove_file(_), do: :ok

  defp repo, do: Escalated.repo()
end
