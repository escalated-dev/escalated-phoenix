defmodule Escalated.Repo.Migrations.ClearGuestChallengeResults do
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  # Proof rows written before this release kept the issued bearer capability in
  # `result` so an identical retry could return it. Replays now rebuild the
  # capability from the grant, so no stored result may keep a live token. A proof
  # consumed before the upgrade can no longer be replayed: its recipient keeps
  # the capability already returned or requests a new code. All tenants' rows are
  # cleared in one statement; nothing else changes.
  def up do
    execute("UPDATE #{@prefix}guest_challenges SET result = NULL WHERE result IS NOT NULL")
  end

  # Cleared results cannot be restored, and older code treats a missing result as
  # a proof that cannot be replayed, so rolling back needs no change.
  def down, do: :ok
end
