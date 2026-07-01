defmodule Escalated.Schemas.Plugin do
  @moduledoc """
  Ecto schema recording the activation state of a host-registered plugin.

  The executable plugin lives in the host application (a module implementing
  the `Escalated.Plugins.Plugin` behaviour, registered via
  `config :escalated, plugins: [...]`). This row only tracks whether an admin
  has activated that plugin by its `slug`. Mirrors the Laravel `Plugin` model.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  @prefix Application.compile_env(:escalated, :table_prefix, "escalated_")

  schema "#{@prefix}plugins" do
    field :slug, :string
    field :is_active, :boolean, default: false
    field :activated_at, :utc_datetime
    field :deactivated_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plugin, attrs) do
    plugin
    |> cast(attrs, [:slug, :is_active, :activated_at, :deactivated_at])
    |> validate_required([:slug])
    |> unique_constraint(:slug)
  end

  @doc "Scope query to activated plugins."
  def active(query \\ __MODULE__) do
    from(p in query, where: p.is_active == true, order_by: [asc: p.slug])
  end

  @doc "Serialize a plugin row for the admin frontend."
  def to_json(%__MODULE__{} = p) do
    %{
      id: p.id,
      slug: p.slug,
      is_active: p.is_active,
      activated_at: p.activated_at,
      deactivated_at: p.deactivated_at,
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end
end
