defmodule Escalated.Plugins.Store do
  @moduledoc """
  Queryable per-plugin key/value data store, backed by `plugin_store` rows.

  Each entry is namespaced by `plugin` slug and `collection`. Keyed entries
  (`get/3`, `set/4`, `delete/3`) address a single row by `key`; `insert/3`
  appends a keyless row. `query/3` returns the matching `data` maps, filtered
  in-memory so the same operator set works across every host database.

  Filters map a JSON field to either a literal (equality) or an operator map.
  Supported operators mirror the Laravel store: `$eq`, `$ne`, `$gt`, `$gte`,
  `$lt`, `$lte`, `$in`, `$nin`.

      Store.set("billing", "invoices", "inv_1", %{"amount" => 50})
      Store.query("billing", "invoices", %{"amount" => %{"$gte" => 25}})
  """
  import Ecto.Query

  alias Escalated.Schemas.PluginStoreRecord

  @doc "Fetch the data map for a keyed entry, or nil if absent."
  def get(plugin, collection, key) do
    case fetch(plugin, collection, key) do
      nil -> nil
      record -> record.data
    end
  end

  @doc "Insert or update the keyed entry's data map."
  def set(plugin, collection, key, data) when is_map(data) do
    repo = Escalated.repo()

    case fetch(plugin, collection, key) do
      nil ->
        %PluginStoreRecord{}
        |> PluginStoreRecord.changeset(%{
          plugin: plugin,
          collection: collection,
          key: key,
          data: data
        })
        |> repo.insert()

      record ->
        record
        |> PluginStoreRecord.changeset(%{data: data})
        |> repo.update()
    end
  end

  @doc "Append a keyless entry to a collection."
  def insert(plugin, collection, data) when is_map(data) do
    repo = Escalated.repo()

    %PluginStoreRecord{}
    |> PluginStoreRecord.changeset(%{plugin: plugin, collection: collection, data: data})
    |> repo.insert()
  end

  @doc "Delete a keyed entry. Returns `{:ok, _}` even when nothing matched."
  def delete(plugin, collection, key) do
    repo = Escalated.repo()

    case fetch(plugin, collection, key) do
      nil -> {:ok, nil}
      record -> repo.delete(record)
    end
  end

  @doc """
  Return the `data` maps in a collection matching `filter` (default: all).
  """
  def query(plugin, collection, filter \\ %{}) do
    repo = Escalated.repo()

    PluginStoreRecord
    |> where([r], r.plugin == ^plugin and r.collection == ^collection)
    |> repo.all()
    |> Enum.map(& &1.data)
    |> Enum.filter(&matches?(&1, filter))
  end

  defp fetch(plugin, collection, key) do
    repo = Escalated.repo()
    repo.get_by(PluginStoreRecord, plugin: plugin, collection: collection, key: key)
  end

  defp matches?(data, filter) when is_map(data) do
    Enum.all?(filter, fn {field, condition} ->
      match_condition?(Map.get(data, to_string(field)), condition)
    end)
  end

  defp matches?(_data, _filter), do: false

  defp match_condition?(actual, condition) do
    if operator_map?(condition) do
      Enum.all?(condition, fn {op, operand} -> apply_operator(op, actual, operand) end)
    else
      actual == condition
    end
  end

  defp operator_map?(condition) when is_map(condition) and map_size(condition) > 0 do
    Enum.all?(Map.keys(condition), &operator_key?/1)
  end

  defp operator_map?(_condition), do: false

  defp operator_key?(key) do
    is_binary(key) and String.starts_with?(key, "$")
  end

  defp apply_operator("$eq", actual, operand), do: actual == operand
  defp apply_operator("$ne", actual, operand), do: actual != operand
  defp apply_operator("$gt", actual, operand), do: term_compare(actual, operand) == :gt
  defp apply_operator("$gte", actual, operand), do: term_compare(actual, operand) in [:gt, :eq]
  defp apply_operator("$lt", actual, operand), do: term_compare(actual, operand) == :lt
  defp apply_operator("$lte", actual, operand), do: term_compare(actual, operand) in [:lt, :eq]
  defp apply_operator("$in", actual, operand) when is_list(operand), do: actual in operand
  defp apply_operator("$nin", actual, operand) when is_list(operand), do: actual not in operand
  defp apply_operator(_unknown, _actual, _operand), do: false

  defp term_compare(a, b) do
    cond do
      a > b -> :gt
      a < b -> :lt
      true -> :eq
    end
  end
end
