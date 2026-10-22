defmodule Mix.Tasks.Escalated.PurgeExpired do
  @shortdoc "Purge expired tickets, attachments and audit logs per retention policy"
  @moduledoc """
  Applies the admin data-retention settings (mirrors the Laravel
  `escalated:purge-expired`): closed tickets, attachments and audit logs older
  than their configured retention are deleted. See
  `Escalated.Services.RetentionPurge` for what goes with a ticket.

  Every setting defaults to `"never"`, which deletes nothing. Closed tickets
  are deleted outright: the Phoenix ticket schema has no soft delete, so there
  is no 30-day grace period as in Laravel.

  Schedule it daily from your host (cron, Quantum, Oban cron, ...). Expired
  guest verification records are purged by `mix escalated.purge_guest_access`,
  which wants a more frequent schedule.

      mix escalated.purge_expired            # delete
      mix escalated.purge_expired --dry-run  # report counts only

  With tenancy enabled it runs once per tenant (or `--tenant ID`).
  """
  use Mix.Task

  alias Escalated.Services.RetentionPurge

  @labels [tickets: "closed tickets", attachments: "attachments", audit_logs: "audit logs"]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")
    Escalated.Tenancy.Maintenance.run(args, &run_for_tenant/1)
  end

  defp run_for_tenant(args) do
    dry_run? = "--dry-run" in args
    counts = RetentionPurge.run(dry_run: dry_run?)

    for {key, label} <- @labels do
      count = Map.fetch!(counts, key)

      Mix.shell().info(
        if dry_run?,
          do: "#{label}: #{count} record(s) past the cutoff (dry run).",
          else: "#{label}: deleted #{count} record(s)."
      )
    end

    suffix = if dry_run?, do: " (dry run)", else: ""
    Mix.shell().info("Escalated: purge-expired complete#{suffix}.")
    counts
  end
end
