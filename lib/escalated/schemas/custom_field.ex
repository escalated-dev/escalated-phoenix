defmodule Escalated.Schemas.CustomField do
  @moduledoc """
  Ecto schema for custom field definitions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @field_types ~w(text textarea number select multi_select checkbox date url)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}custom_fields" do
    field :name, :string
    field :slug, :string
    field :field_type, :string, default: "text"
    field :description, :string
    field :is_required, :boolean, default: false
    field :options, {:array, :string}
    field :default_value, :string
    field :entity_type, :string, default: "ticket"
    field :position, :integer, default: 0
    field :is_active, :boolean, default: true

    has_many :values, Escalated.Schemas.CustomFieldValue

    timestamps(type: :utc_datetime)
  end

  def field_types, do: @field_types

  @doc false
  def changeset(custom_field, attrs) do
    custom_field
    |> cast(attrs, [:name, :slug, :field_type, :description, :is_required, :options, :default_value, :entity_type, :position, :is_active])
    |> validate_required([:name, :field_type, :entity_type])
    |> validate_inclusion(:field_type, @field_types)
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
