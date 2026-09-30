defmodule Escalated.Tenancy.Preloader do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Tenancy
  alias Escalated.Tenancy.Repo

  def load(nil, _, _), do: nil
  def load([], _, _), do: []

  def load(records, preloads, opts) when is_list(records) do
    Enum.each(records, &Tenancy.assert_record!/1)
    Enum.reduce(List.wrap(preloads), records, &load_association(&2, &1, opts))
  end

  def load(record, preloads, opts), do: load([record], preloads, opts) |> hd()

  defp load_association(records, name, opts) when is_atom(name),
    do: load_association(records, {name, []}, opts)

  defp load_association([first | _] = records, {name, spec}, opts) do
    assoc = first.__struct__.__schema__(:association, name) || Tenancy.deny!()
    {query, nested} = spec(spec, assoc.related)
    owner_key = assoc.owner_key
    ids = records |> Enum.map(&Map.fetch!(&1, owner_key)) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    grouped =
      case assoc do
        %Ecto.Association.ManyToMany{
          join_through: pivot,
          join_keys: [{left, _}, {right, related_key}]
        } ->
          from(related in query,
            join: link in ^pivot,
            on: field(link, ^right) == field(related, ^related_key),
            where: field(link, ^left) in ^ids,
            select: {field(link, ^left), related}
          )
          |> Repo.all()
          |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

        %{related_key: key} ->
          from(related in query, where: field(related, ^key) in ^ids)
          |> Repo.all()
          |> Enum.group_by(&Map.fetch!(&1, key))

        _ ->
          Tenancy.deny!()
      end

    Enum.map(records, fn record ->
      associated = Map.get(grouped, Map.fetch!(record, owner_key), []) |> load(nested, opts)
      value = if assoc.cardinality == :one, do: List.first(associated), else: associated
      Map.put(record, name, value)
    end)
  end

  defp spec(%Ecto.Query{} = query, _), do: {query, []}
  defp spec({%Ecto.Query{} = query, nested}, _), do: {query, nested}

  defp spec(nested, schema) when is_list(nested) or is_atom(nested),
    do: {Ecto.Queryable.to_query(schema), nested}

  defp spec(_, _), do: Tenancy.deny!()
end
