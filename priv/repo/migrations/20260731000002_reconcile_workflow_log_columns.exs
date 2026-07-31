defmodule Escalated.Repo.Migrations.ReconcileWorkflowLogColumns do
  @moduledoc """
  Reconciles the `workflow_logs` table with `Escalated.Schemas.WorkflowLog`.

  The original parity-gap migration created the table with a NOT NULL
  `status` column but none of the `conditions_matched`, `started_at`, or
  `completed_at` columns the schema (and `WorkflowRunner`) actually write.
  Because the runner was never invoked, the mismatch never surfaced.
  Wiring the engine into the ticket lifecycle now exercises these inserts,
  so the missing columns are added here. `status` stays and is populated by
  the runner ("success" / "failed" / "skipped").

  Additive only (`add column`) so it applies cleanly on SQLite (test) and
  every host database (Postgres / MySQL).
  """
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table("#{@prefix}workflow_logs") do
      add :conditions_matched, :boolean, default: true
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
    end
  end
end
