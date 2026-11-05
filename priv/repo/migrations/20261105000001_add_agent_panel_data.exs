defmodule Escalated.Repo.Migrations.AddAgentPanelData do
  @moduledoc """
  The agent panel's data (escalated-developer-context ADR
  2026-11-05-agent-panel-data):

    * `tickets.last_customer_activity_at` and `ticket_reads`, the per-agent
      unread markers. Existing tickets get no activity, so none turn unread on
      upgrade;
    * `customer_presence`, when each customer was last seen;
    * `agent_profiles.chat_status`, the agent's own Online / Away / Offline
      status (`offline` until they set it);
    * `notifications`, the agents' in-app notifications.

  New tables and nullable or defaulted columns, created the same way on
  SQLite, PostgreSQL and MySQL. Unique keys lead with `tenant_id`, as every
  tenant-owned table's do.
  """
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    alter table(@prefix <> "tickets") do
      add :last_customer_activity_at, :utc_datetime
    end

    create index(@prefix <> "tickets", [:last_customer_activity_at], name: name("activity"))

    alter table(@prefix <> "agent_profiles") do
      add :chat_status, :string, size: 16, null: false, default: "offline"
    end

    create table(@prefix <> "ticket_reads") do
      add :tenant_id, :string, tenant_options()
      add :ticket_id, :bigint, null: false
      add :user_id, :string, size: 191, null: false
      add :last_read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(@prefix <> "ticket_reads", [:tenant_id, :user_id, :ticket_id],
             name: name("reads_unique")
           )

    create index(@prefix <> "ticket_reads", [:ticket_id], name: name("reads_ticket"))

    create table(@prefix <> "customer_presence") do
      add :tenant_id, :string, tenant_options()
      add :subject_type, :string, size: 32, null: false
      add :subject_id, :string, size: 191, null: false
      add :last_seen_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             @prefix <> "customer_presence",
             [:tenant_id, :subject_type, :subject_id],
             name: name("presence_unique")
           )

    create table(@prefix <> "notifications", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :string, tenant_options()
      add :user_id, :string, size: 191, null: false
      add :type, :string, size: 64, null: false
      add :data, :map, null: false
      add :read_at, :utc_datetime
      add :inserted_at, :utc_datetime, null: false
    end

    create index(@prefix <> "notifications", [:tenant_id, :user_id, :read_at],
             name: name("notifications_user")
           )
  end

  defp tenant_options do
    opts = [size: 128, null: false, default: ""]

    if repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: Keyword.put(opts, :collation, "utf8mb4_bin"),
      else: opts
  end

  # Bounded names also work with a custom prefix and PostgreSQL's 63-byte cap.
  defp name(purpose) do
    hash =
      :crypto.hash(:sha256, @prefix <> "agent_panel:" <> purpose) |> Base.encode16(case: :lower)

    "escalated_panel_" <> binary_part(hash, 0, 24)
  end
end
