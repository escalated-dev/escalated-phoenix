defmodule Escalated.Repo.Migrations.AddVerifiedGuestAccess do
  use Ecto.Migration
  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def up do
    create table("#{@prefix}guest_challenges", primary_key: false) do
      add :id, :uuid, primary_key: true
      add :tenant_id, :string, tenant_options()
      add :email, :string, null: false, size: 255
      add :purpose, :string, null: false, size: 16
      add :code_hash, :string, null: false, size: 64
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
      add :request_hash, :string, size: 64
      add :result, :map
      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}guest_challenges", [:tenant_id, :expires_at])
    create unique_index("#{@prefix}guest_challenges", [:tenant_id, :id])

    create table("#{@prefix}guest_grants") do
      add :tenant_id, :string, tenant_options()
      add :ticket_id, references("#{@prefix}tickets", on_delete: :delete_all), null: false
      add :purpose, :string, null: false, size: 16
      add :email_hash, :string, null: false, size: 64
      add :nonce_hash, :string, null: false, size: 64
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}guest_grants", [:tenant_id, :ticket_id, :purpose])
    create index("#{@prefix}guest_grants", [:tenant_id, :expires_at])

    # Global anti-abuse state: selecting another merchant must not reset mail limits.
    create table("#{@prefix}guest_mailbox_budgets", primary_key: false) do
      add :mailbox_hash, :string, size: 64, primary_key: true
      add :attempts, :integer, null: false, default: 0
      add :expires_at, :utc_datetime, null: false
    end

    create index("#{@prefix}guest_mailbox_budgets", [:expires_at])
  end

  def down do
    # Even an expired row is not silently discarded during rollback. Run the
    # bounded expiry cleanup first; active grants and mail budgets must survive.
    tables = ~w(guest_challenges guest_grants guest_mailbox_budgets)

    for name <- tables do
      source = "#{@prefix}#{name}"

      if repo().exists?(source) do
        raise "Cannot roll back verified guest access while #{source} contains records. " <>
                "Let active records expire, run mix escalated.purge_guest_access for all tenants, and retry."
      end
    end

    # All guards run before any destructive DDL, including on MySQL.
    for name <- tables, do: drop(table("#{@prefix}#{name}"))
  end

  defp tenant_options do
    opts = [size: 128, null: false, default: ""]

    if repo().__adapter__() == Ecto.Adapters.MyXQL,
      do: Keyword.put(opts, :collation, "utf8mb4_bin"),
      else: opts
  end
end
