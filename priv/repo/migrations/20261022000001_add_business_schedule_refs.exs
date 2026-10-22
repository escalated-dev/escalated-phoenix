defmodule Escalated.Repo.Migrations.AddBusinessScheduleRefs do
  @moduledoc """
  `business_schedule_id` on SLA policies and departments: the schedule SLA
  deadlines count against when business hours apply
  (`Escalated.Services.SlaService`). Plain nullable ids with an index, no
  foreign key, so the columns add and drop the same way on SQLite, PostgreSQL
  and MySQL. Deleting a schedule clears them; tenancy validates them as local
  references. Existing rows get nil, which keeps their current deadlines.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    for table <- ["sla_policies", "departments"] do
      alter table(@prefix <> table) do
        add :business_schedule_id, :bigint
      end

      create index(@prefix <> table, [:business_schedule_id], name: index_name(table))
    end
  end

  defp index_name(table) do
    hash =
      :crypto.hash(:sha256, @prefix <> table <> "business_schedule")
      |> Base.encode16(case: :lower)

    "escalated_bsched_" <> binary_part(hash, 0, 24)
  end
end
