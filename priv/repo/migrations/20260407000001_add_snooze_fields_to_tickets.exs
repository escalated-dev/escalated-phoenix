defmodule Escalated.Repo.Migrations.AddSnoozeFieldsToTickets do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table("#{@prefix}tickets") do
      add :snoozed_until, :utc_datetime
      add :snoozed_by, :integer
      add :status_before_snooze, :string
    end

    create index("#{@prefix}tickets", [:snoozed_until],
      where: "snoozed_until IS NOT NULL",
      name: "#{@prefix}tickets_snoozed_until_index"
    )
  end
end
