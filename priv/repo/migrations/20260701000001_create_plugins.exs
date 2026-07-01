defmodule Escalated.Repo.Migrations.CreatePlugins do
  use Ecto.Migration

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  def change do
    # Activation state for host-registered plugin modules. The plugin code
    # itself lives in the host application (registered via
    # `config :escalated, plugins: [...]`); this table only records which
    # plugins the admin has switched on. Mirrors the Laravel `plugins` table.
    create table("#{@prefix}plugins") do
      add :slug, :string, null: false
      add :is_active, :boolean, null: false, default: false
      add :activated_at, :utc_datetime
      add :deactivated_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index("#{@prefix}plugins", [:slug])
    create index("#{@prefix}plugins", [:is_active])

    # Queryable per-plugin data store (key/value + JSON payload), namespaced
    # by plugin and collection. Mirrors the Laravel `plugin_store` table.
    create table("#{@prefix}plugin_store") do
      add :plugin, :string, null: false
      add :collection, :string, null: false
      add :key, :string
      add :data, :map

      timestamps(type: :utc_datetime)
    end

    create index("#{@prefix}plugin_store", [:plugin, :collection, :key])
  end
end
