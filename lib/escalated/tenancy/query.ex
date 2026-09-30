defmodule Escalated.Tenancy.Query do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Tenancy
  alias Escalated.Tenancy.Tables

  # Fixed atoms: query construction must not grow the VM's atom table.
  @bindings for index <- 0..64, do: String.to_atom("escalated_tenant_#{index}")

  def entry!(schema) when is_atom(schema) do
    Enum.find(Tables.entries(), &(&1.schema == schema)) || Tenancy.deny!()
  end

  def entry!(name) when is_binary(name) do
    Enum.find(Tables.entries(), &(Escalated.table_name(&1.name) == name)) || Tenancy.deny!()
  end

  def scope(queryable) do
    query = Ecto.Queryable.to_query(queryable)
    tenant = Tenancy.current_id!()

    # Package queries use ordinary table joins. Unsupported host query forms
    # are rejected rather than accidentally running an unscoped nested query.
    if query.combinations != [] or query.with_ctes != nil or length(query.joins) > 64,
      do: Tenancy.deny!()

    if query.prefix != nil or query.from.prefix != nil, do: Tenancy.deny!()

    if Enum.any?(
         query.joins,
         &(&1.prefix != nil or &1.assoc != nil or &1.qual not in [:inner, :cross])
       ),
       do: Tenancy.deny!()

    reject_subqueries!(query)

    entry!(source(query.from.source))

    Enum.reduce(0..length(query.joins), query, fn index, scoped ->
      entry!(binding_source!(query, index))
      name = Enum.at(@bindings, index)
      scoped = %{scoped | aliases: Map.put(scoped.aliases, name, index)}

      where(scoped, [{^name, row}], field(row, :tenant_id) == ^tenant)
    end)
  end

  defp binding_source!(query, 0), do: source(query.from.source)

  defp binding_source!(query, index) do
    case Enum.at(query.joins, index - 1) do
      %{source: source} -> source(source)
    end
  end

  defp source({name, schema}) when is_atom(schema) and not is_nil(schema) do
    if name not in [nil, Escalated.table_name(entry!(schema).name)], do: Tenancy.deny!()
    schema
  end

  defp source({name, nil}) when is_binary(name), do: name
  defp source(_), do: Tenancy.deny!()

  defp reject_subqueries!(%Ecto.SubQuery{}), do: Tenancy.deny!()

  defp reject_subqueries!(map) when is_map(map) do
    map |> Map.values() |> Enum.each(&reject_subqueries!/1)
  end

  defp reject_subqueries!(list) when is_list(list), do: Enum.each(list, &reject_subqueries!/1)

  defp reject_subqueries!(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.each(&reject_subqueries!/1)

  defp reject_subqueries!(_), do: :ok
end
