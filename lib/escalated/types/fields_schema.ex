defmodule Escalated.Types.FieldsSchema do
  @moduledoc """
  A custom object's `fields_schema` (a list of `%{"name", "type", ...}`), kept
  in the existing `field_definitions` map column.

  The column is a JSON map (`jsonb` on PostgreSQL), which Ecto's `:map` type
  only fills with a map, so the list is stored as `%{"fields" => list}`. A row
  written before as a map of definitions keyed by name reads back as a list.
  """
  use Ecto.Type

  @impl true
  def type, do: :map

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(list) when is_list(list), do: {:ok, list}
  def cast(%{} = map), do: {:ok, from_map(map)}
  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}
  def load(%{} = map), do: {:ok, from_map(map)}
  def load(list) when is_list(list), do: {:ok, list}
  def load(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(list) when is_list(list), do: {:ok, %{"fields" => list}}
  def dump(_), do: :error

  defp from_map(%{"fields" => list}) when is_list(list), do: list

  defp from_map(map) do
    map
    |> Enum.sort_by(fn {name, _} -> to_string(name) end)
    |> Enum.map(fn
      {name, %{} = definition} -> Map.put(stringify(definition), "name", to_string(name))
      {name, type} -> %{"name" => to_string(name), "type" => to_string(type)}
    end)
  end

  defp stringify(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
end
