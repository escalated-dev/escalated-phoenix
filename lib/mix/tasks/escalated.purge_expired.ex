defmodule Mix.Tasks.Escalated.PurgeExpired do
  @shortdoc "Purge expired attachments and audit logs per retention policy"
  @moduledoc """
  Purges attachments and audit logs older than the configured retention
  policy (mirrors the Laravel `escalated:purge-expired` for those types).

  Closed-ticket retention is intentionally NOT enforced here: the Laravel
  command soft-deletes tickets with a grace period, which depends on a
  `deleted_at` column the Phoenix ticket schema does not have. Until that
  lands, the task only *reports* the closed-ticket candidate count.

  Pass `--dry-run` to report counts without deleting.
  """
  use Mix.Task

  import Ecto.Query

  alias Escalated.Schemas.{Attachment, AuditLog, Ticket}
  alias Escalated.Services.SettingsService
  alias Escalated.Support.Retention

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    dry_run? = "--dry-run" in args
    repo = Escalated.repo()

    purge(repo, Attachment, "retention_attachments", "attachments", dry_run?)
    purge(repo, AuditLog, "retention_audit_logs", "audit logs", dry_run?)
    report_ticket_candidates(repo)

    suffix = if dry_run?, do: " (dry run)", else: ""
    Mix.shell().info("Escalated: purge-expired complete#{suffix}.")
  end

  defp purge(repo, schema, setting_key, label, dry_run?) do
    case Retention.cutoff_for(SettingsService.get_or_default(setting_key, "never")) do
      nil ->
        Mix.shell().info("#{label}: retention 'never' — skipping.")

      cutoff ->
        query = from(r in schema, where: r.inserted_at < ^cutoff)
        count = repo.aggregate(query, :count)
        delete_or_report(repo, query, count, label, dry_run?)
    end
  end

  defp delete_or_report(_repo, _query, count, label, true) do
    Mix.shell().info("#{label}: #{count} record(s) older than cutoff (dry run).")
  end

  defp delete_or_report(repo, query, count, label, false) do
    repo.delete_all(query)
    Mix.shell().info("#{label}: deleted #{count} record(s).")
  end

  defp report_ticket_candidates(repo) do
    case Retention.cutoff_for(SettingsService.get_or_default("retention_closed_tickets", "never")) do
      nil ->
        :ok

      cutoff ->
        count =
          repo.aggregate(
            from(t in Ticket, where: t.status == "closed" and t.closed_at < ^cutoff),
            :count
          )

        Mix.shell().info(
          "closed tickets: #{count} candidate(s) older than cutoff (purge deferred — manual review)."
        )
    end
  end
end
