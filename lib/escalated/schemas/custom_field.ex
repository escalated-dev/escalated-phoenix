defmodule Escalated.Schemas.CustomField do
  @moduledoc """
  Ecto schema for custom field definitions.

  The columns keep their original names (`field_type`, `entity_type`,
  `is_required`, `is_active`); the admin pages and ticket payloads use
  escalated-laravel's (`type`, `context`, `required`, `active`), mapped in
  `Escalated.Services.CustomFieldService`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @field_types ~w(text textarea number select multi_select checkbox date url)

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}custom_fields" do
    field :tenant_id, :string, default: ""
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
    field :placeholder, :string
    field :validation_rules, Escalated.Types.JsonText
    field :conditions, Escalated.Types.JsonText

    has_many :values, Escalated.Schemas.CustomFieldValue

    timestamps(type: :utc_datetime)
  end

  def field_types, do: @field_types

  @doc false
  def changeset(custom_field, attrs) do
    custom_field
    |> cast(attrs, [
      :name,
      :slug,
      :field_type,
      :description,
      :is_required,
      :options,
      :default_value,
      :entity_type,
      :position,
      :is_active,
      :placeholder,
      :validation_rules,
      :conditions
    ])
    |> validate_required([:name, :field_type, :entity_type])
    |> validate_inclusion(:field_type, @field_types)
    |> unique_constraint(:slug)
    |> Escalated.Tenancy.Constraints.add_unique_constraints()
    |> maybe_generate_slug()
  end

  @doc "The slug a field named `name` gets: lowercase words joined by `_`."
  def slugify(name) do
    name
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp maybe_generate_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when slug in [nil, ""] ->
        put_change(changeset, :slug, slugify(get_field(changeset, :name) || ""))

      _ ->
        changeset
    end
  end
end
