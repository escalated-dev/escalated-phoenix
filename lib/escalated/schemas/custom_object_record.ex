defmodule Escalated.Schemas.CustomObjectRecord do
  @moduledoc """
  Ecto schema for records belonging to a custom object.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "#{Application.compile_env(:escalated, :table_prefix, "escalated_")}custom_object_records" do
    field :title, :string
    field :data, :map, default: %{}
    field :linked_entity_type, :string
    field :linked_entity_id, :integer

    belongs_to :custom_object, Escalated.Schemas.CustomObject

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:custom_object_id, :title, :data, :linked_entity_type, :linked_entity_id])
    |> validate_required([:custom_object_id])
  end

  def field_value(%__MODULE__{data: data}, key) when is_map(data), do: Map.get(data, key)
  def field_value(_, _), do: nil
end
