defmodule Escalated.Repo.Migrations.CreateTicketStatuses do
  @moduledoc """
  Custom ticket statuses (`Escalated.Schemas.TicketStatus`): admin-defined
  sub-statuses, each in one of five categories, plus a nullable
  `ticket_status_id` on tickets holding a ticket's custom status.

  One system row per built-in status is seeded for the single-tenant
  namespace (`tenant_id` ""); a merchant namespace gets its system rows the
  first time its admin opens the statuses page
  (`Escalated.Services.TicketStatusService.ensure_system_statuses/0`).

  `ticket_status_id` is a plain nullable id with an index, no foreign key, so
  the column adds and drops the same way on SQLite, PostgreSQL and MySQL;
  deleting a status clears it from its tickets. Existing tickets get nil and
  keep their status.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  # slug => {label, colour, category}. A copy of TicketStatus.system_statuses/0
  # as it was when this migration was written, so the migration never changes.
  @system [
    {"open", "Open", "#3B82F6", "open"},
    {"in_progress", "In Progress", "#8B5CF6", "open"},
    {"waiting_on_customer", "Waiting on Customer", "#F59E0B", "pending"},
    {"waiting_on_agent", "Waiting on Agent", "#F97316", "open"},
    {"escalated", "Escalated", "#EF4444", "open"},
    {"resolved", "Resolved", "#10B981", "solved"},
    {"closed", "Closed", "#6B7280", "solved"},
    {"reopened", "Reopened", "#3B82F6", "open"},
    {"snoozed", "Snoozed", "#6B7280", "on_hold"},
    {"live", "Live", "#06B6D4", "open"}
  ]

  def up do
    create table(@prefix <> "ticket_statuses") do
      add :tenant_id, :string, tenant_options()
      add :label, :string, null: false, size: 255
      add :slug, :string, null: false, size: 255
      add :category, :string, null: false, size: 20
      add :color, :string, null: false, size: 20, default: "#6b7280"
      add :description, :text
      add :position, :integer, null: false, default: 0
      add :is_default, :boolean, null: false, default: false
      add :is_system, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(@prefix <> "ticket_statuses", [:tenant_id, :slug],
             name: @prefix <> "ticket_statuses_slug_index"
           )

    create index(@prefix <> "ticket_statuses", [:tenant_id, :category, :position],
             name: index_name("ticket_statuses", "category")
           )

    alter table(@prefix <> "tickets") do
      add :ticket_status_id, :bigint
    end

    create index(@prefix <> "tickets", [:ticket_status_id],
             name: index_name("tickets", "ticket_status")
           )

    flush()

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      @system
      |> Enum.with_index()
      |> Enum.map(fn {{slug, label, color, category}, position} ->
        %{
          tenant_id: "",
          label: label,
          slug: slug,
          category: category,
          color: color,
          position: position,
          is_default: boolean(false),
          is_system: boolean(true),
          inserted_at: now,
          updated_at: now
        }
      end)

    repo().insert_all(@prefix <> "ticket_statuses", rows)
  end

  def down do
    drop index(@prefix <> "tickets", [:ticket_status_id],
           name: index_name("tickets", "ticket_status")
         )

    alter table(@prefix <> "tickets") do
      remove :ticket_status_id
    end

    drop table(@prefix <> "ticket_statuses")
  end

  # A schemaless insert passes values through as they are, and SQLite would
  # store `true` as the text "true"; it reads booleans as 1 and 0.
  defp boolean(value) do
    if repo().__adapter__() == Ecto.Adapters.SQLite3,
      do: if(value, do: 1, else: 0),
      else: value
  end

  defp tenant_options do
    opts = [size: 128, null: false, default: ""]

    if repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: Keyword.put(opts, :collation, "utf8mb4_bin"),
      else: opts
  end

  # Bounded names also work with a custom prefix and PostgreSQL's 63-byte cap.
  defp index_name(table, purpose) do
    hash =
      :crypto.hash(:sha256, @prefix <> table <> ":" <> purpose) |> Base.encode16(case: :lower)

    "escalated_tstatus_" <> binary_part(hash, 0, 24)
  end
end
