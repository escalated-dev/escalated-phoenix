defmodule Escalated.Repo.Migrations.AddSnoozeFieldsToTickets do
  use Ecto.Migration

  alias Escalated.UserKey

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table("#{@prefix}tickets") do
      add :snoozed_until, :utc_datetime
      add :snoozed_by, UserKey.migration_type()
      add :status_before_snooze, :string
    end

    # A partial index everywhere that has them. MySQL does not -- Ecto refuses
    # the migration outright ("MySQL adapter does not support where in
    # indexes"), so the engine could not be installed there at all. A plain
    # index covers the same queries; it is only larger, because it also holds
    # the rows that are not snoozed.
    create index("#{@prefix}tickets", [:snoozed_until],
             where: snoozed_index_predicate(),
             name: "#{@prefix}tickets_snoozed_until_index"
           )
  end

  defp snoozed_index_predicate do
    case repo().__adapter__() do
      Ecto.Adapters.MyXQL -> nil
      _ -> "snoozed_until IS NOT NULL"
    end
  end
end
