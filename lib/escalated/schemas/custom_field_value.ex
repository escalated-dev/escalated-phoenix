defmodule Escalated.Schemas.CustomFieldValue do
  @moduledoc """
  Ecto schema for custom field values attached to entities.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}custom_field_values" do
    field :entity_type, :string, default: "ticket"
    field :entity_id, :integer
    field :value, :string

    belongs_to :custom_field, Escalated.Schemas.CustomField

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(custom_field_value, attrs) do
    custom_field_value
    |> cast(attrs, [:custom_field_id, :entity_type, :entity_id, :value])
    |> validate_required([:custom_field_id, :entity_type, :entity_id])
    |> unique_constraint([:custom_field_id, :entity_type, :entity_id], name: :unique_field_entity)
  end
end
