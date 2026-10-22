defmodule Escalated.Services.RetentionPurgeTest do
  @moduledoc """
  `mix escalated.purge_expired` (and `RetentionPurge`, which it runs) against
  the data-retention settings, as escalated-laravel's `escalated:purge-expired`.
  """
  use Escalated.DataCase, async: false

  import Ecto.Query

  alias Escalated.Schemas.{
    Attachment,
    AuditLog,
    Reply,
    SatisfactionRating,
    Tag,
    Ticket,
    TicketFollower,
    TicketTag
  }

  alias Escalated.Services.{RetentionPurge, SettingsService}

  defp repo, do: Escalated.repo()

  defp days_ago(days),
    do: DateTime.utc_now() |> DateTime.add(-days * 86_400) |> DateTime.truncate(:second)

  defp ticket!(status, closed_at) do
    ticket =
      %Ticket{}
      |> Ticket.changeset(%{subject: "S", description: "d"})
      |> repo().insert!()

    ticket
    |> Ecto.Changeset.change(%{status: status, closed_at: closed_at})
    |> repo().update!()
  end

  defp attachment!(attrs) do
    %Attachment{}
    |> Attachment.changeset(
      Map.merge(%{original_filename: "a.txt", storage_key: "a.txt", size: 1}, attrs)
    )
    |> repo().insert!()
  end

  defp age!(struct, days) do
    struct |> Ecto.Changeset.change(inserted_at: days_ago(days)) |> repo().update!()
  end

  defp audit_log!(days) do
    %AuditLog{}
    |> AuditLog.changeset(%{action: "updated", entity_type: "ticket"})
    |> repo().insert!()
    |> age!(days)
  end

  defp exists?(schema, id), do: repo().get(schema, id) != nil

  describe "with every setting at the default ('never')" do
    test "touches nothing" do
      old = ticket!("closed", days_ago(4000))
      log = audit_log!(4000)
      file = age!(attachment!(%{}), 4000)

      assert RetentionPurge.run() == %{tickets: 0, attachments: 0, audit_logs: 0}

      assert exists?(Ticket, old.id)
      assert exists?(AuditLog, log.id)
      assert exists?(Attachment, file.id)
    end
  end

  describe "closed-ticket retention" do
    setup do
      SettingsService.set("retention_closed_tickets", "1_year", "retention")
      :ok
    end

    test "deletes closed tickets past the cutoff with their dependent rows" do
      old = ticket!("closed", days_ago(400))
      reply = repo().insert!(Reply.changeset(%Reply{}, %{body: "b", ticket_id: old.id}))
      tag = repo().insert!(%Tag{name: "t-#{old.id}"})
      repo().insert!(%TicketTag{ticket_id: old.id, tag_id: tag.id})
      repo().insert!(%TicketFollower{ticket_id: old.id, user_id: "5"})

      repo().insert!(
        SatisfactionRating.changeset(%SatisfactionRating{}, %{ticket_id: old.id, rating: 5})
      )

      file = attachment!(%{ticket_id: old.id})

      recent = ticket!("closed", days_ago(10))
      open = ticket!("open", nil)
      resolved = ticket!("resolved", days_ago(400))

      assert %{tickets: 1} = RetentionPurge.run()

      refute exists?(Ticket, old.id)
      refute exists?(Reply, reply.id)
      refute exists?(Attachment, file.id)
      assert repo().aggregate(from(t in TicketTag, where: t.ticket_id == ^old.id), :count) == 0

      assert repo().aggregate(from(f in TicketFollower, where: f.ticket_id == ^old.id), :count) ==
               0

      assert repo().aggregate(
               from(r in SatisfactionRating, where: r.ticket_id == ^old.id),
               :count
             ) ==
               0

      assert exists?(Tag, tag.id)
      assert exists?(Ticket, recent.id)
      assert exists?(Ticket, open.id)
      assert exists?(Ticket, resolved.id)
    end

    test "a ticket merged into a purged one is kept and unlinked" do
      target = ticket!("closed", days_ago(400))
      source = ticket!("open", nil)
      source |> Ecto.Changeset.change(merged_into_id: target.id) |> repo().update!()

      RetentionPurge.run()

      refute exists?(Ticket, target.id)
      assert repo().get!(Ticket, source.id).merged_into_id == nil
    end

    test "a dry run deletes nothing and reports the count" do
      old = ticket!("closed", days_ago(400))

      assert %{tickets: 1} = RetentionPurge.run(dry_run: true)
      assert exists?(Ticket, old.id)
    end
  end

  describe "attachment retention" do
    setup do
      SettingsService.set("retention_attachments", "1_year", "retention")
      dir = Path.join(System.tmp_dir!(), "esc-purge-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      previous = Application.get_env(:escalated, :upload_dir)
      Application.put_env(:escalated, :upload_dir, dir)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:escalated, :upload_dir, previous),
          else: Application.delete_env(:escalated, :upload_dir)

        File.rm_rf!(dir)
      end)

      %{dir: dir}
    end

    test "deletes old attachments and their stored files", %{dir: dir} do
      File.write!(Path.join(dir, "old.txt"), "x")
      File.write!(Path.join(dir, "new.txt"), "x")
      old = age!(attachment!(%{storage_key: "old.txt"}), 400)
      new = attachment!(%{storage_key: "new.txt"})

      assert %{attachments: 1} = RetentionPurge.run()

      refute exists?(Attachment, old.id)
      assert exists?(Attachment, new.id)
      refute File.exists?(Path.join(dir, "old.txt"))
      assert File.exists?(Path.join(dir, "new.txt"))
    end

    test "never deletes a file outside the upload directory", %{dir: dir} do
      outside = Path.join(Path.dirname(dir), "esc-purge-outside-#{System.unique_integer()}")
      File.write!(outside, "keep")
      on_exit(fn -> File.rm(outside) end)

      age!(attachment!(%{storage_key: "../" <> Path.basename(outside)}), 400)

      assert %{attachments: 1} = RetentionPurge.run()
      assert File.exists?(outside)
    end
  end

  describe "audit-log retention" do
    test "deletes audit logs past the cutoff only" do
      SettingsService.set("retention_audit_logs", "90_days", "retention")
      old = audit_log!(100)
      recent = audit_log!(10)

      assert %{audit_logs: 1} = RetentionPurge.run()
      refute exists?(AuditLog, old.id)
      assert exists?(AuditLog, recent.id)
    end
  end

  describe "mix escalated.purge_expired" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
      SettingsService.set("retention_closed_tickets", "1_year", "retention")
      :ok
    end

    test "--dry-run reports and deletes nothing" do
      old = ticket!("closed", days_ago(400))

      Mix.Tasks.Escalated.PurgeExpired.run(["--dry-run"])

      assert exists?(Ticket, old.id)

      assert_received {:mix_shell, :info,
                       ["closed tickets: 1 record(s) past the cutoff (dry run)."]}
    end

    test "purges closed tickets" do
      old = ticket!("closed", days_ago(400))

      Mix.Tasks.Escalated.PurgeExpired.run([])

      refute exists?(Ticket, old.id)
      assert_received {:mix_shell, :info, ["closed tickets: deleted 1 record(s)."]}
    end
  end
end
