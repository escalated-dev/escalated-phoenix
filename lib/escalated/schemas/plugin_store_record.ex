defmodule Escalated.Schemas.PluginStoreRecord do
  @moduledoc """
  Ecto schema for a single row in the queryable per-plugin data store.

  Each row is namespaced by `plugin` (slug) and `collection`, with an optional
  `key` for keyed lookups and a JSON `data` payload. Plugins read/write these
  rows through `Escalated.Plugins.Store`. Mirrors the Laravel
  `PluginStoreRecord` model backing the `plugin_store` table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}plugin_store" do
    field :plugin, :string
    field :collection, :string
    field :key, :string
    field :data, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:plugin, :collection, :key, :data])
    |> validate_required([:plugin, :collection])
  end
end
