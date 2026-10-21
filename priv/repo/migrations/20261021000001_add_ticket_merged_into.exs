defmodule Escalated.Repo.Migrations.AddTicketMergedInto do
  @moduledoc """
  `merged_into_id` on tickets: the ticket a merged ticket was merged into
  (`Escalated.Services.TicketMergeService`). A plain nullable id with an index,
  no foreign key, so the column adds and drops the same way on SQLite,
  PostgreSQL and MySQL. Tenancy validates it as a local reference.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table(@prefix <> "tickets") do
      add :merged_into_id, :bigint
    end

    create index(@prefix <> "tickets", [:merged_into_id], name: index_name())
  end

  defp index_name do
    hash = :crypto.hash(:sha256, @prefix <> "merged_into") |> Base.encode16(case: :lower)
    "escalated_merged_" <> binary_part(hash, 0, 24)
  end
end
