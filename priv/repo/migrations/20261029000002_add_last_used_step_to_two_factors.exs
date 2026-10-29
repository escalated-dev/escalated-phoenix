defmodule Escalated.Repo.Migrations.AddLastUsedStepToTwoFactors do
  @moduledoc """
  The TOTP time step of the last code accepted for a user's enrolment, so the
  same code (or an older one) cannot be used again inside its validity window
  (ADR 2026-10-29-configurable-access-features). Nullable: existing rows have
  accepted no code yet. Adds and drops the same way on SQLite, PostgreSQL and
  MySQL.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table(@prefix <> "two_factors") do
      add :last_used_step, :bigint
    end
  end
end
