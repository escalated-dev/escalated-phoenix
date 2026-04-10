defmodule Escalated.Schemas.CustomObject do
  @moduledoc """
  Ecto schema for custom object definitions (enterprise custom data models).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}custom_objects" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :field_definitions, :map
    field :is_active, :boolean, default: true

    has_many :records, Escalated.Schemas.CustomObjectRecord

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(custom_object, attrs) do
    custom_object
    |> cast(attrs, [:name, :slug, :description, :field_definitions, :is_active])
    |> validate_required([:name])
    |> unique_constraint(:slug)
    |> maybe_generate_slug()
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        name = get_field(changeset, :name) || ""
        slug = name |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
        put_change(changeset, :slug, slug)

      _ ->
        changeset
    end
  end
end
