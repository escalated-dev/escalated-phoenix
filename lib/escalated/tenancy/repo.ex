defmodule Escalated.Tenancy.Repo do
  @moduledoc """
  Tenant-scoped data access used by all package services when tenancy is enabled.

  This facade deliberately supports the package's ordinary Ecto query surface.
  Raw SQL, query unions/CTEs, joined preloads, bulk ownership changes and arbitrary
  upsert expressions are rejected. Trusted host migrations use storage_repo/0.
  """
  import Ecto.Query, only: [where: 2, where: 3]
  alias Escalated.Tenancy
  alias Escalated.Tenancy.{Preloader, Query, Writes}

  def __adapter__, do: raw().__adapter__()

  def all(queryable, opts \\ []) do
    options!(opts)
    query = Query.scope(queryable)
    if query.assocs != [], do: Tenancy.deny!()
    preloads = query.preloads
    rows = raw().all(%{query | preloads: []}, opts)
    if preloads == [], do: rows, else: preload(rows, preloads)
  end

  def one(queryable, opts \\ []) do
    case all(queryable, opts) do
      [] -> nil
      [row] -> row
      rows -> raise Ecto.MultipleResultsError, queryable: queryable, count: length(rows)
    end
  end

  def one!(queryable, opts \\ []),
    do: one(queryable, opts) || raise(Ecto.NoResultsError, queryable: queryable)

  def get(query, id, opts \\ []), do: one(where(query, [row], field(row, :id) == ^id), opts)

  def get!(query, id, opts \\ []),
    do: get(query, id, opts) || raise(Ecto.NoResultsError, queryable: query)

  def get_by(query, clauses, opts \\ []), do: one(where(query, ^clauses), opts)

  def get_by!(query, clauses, opts \\ []),
    do: get_by(query, clauses, opts) || raise(Ecto.NoResultsError, queryable: query)

  def exists?(query, opts \\ []) do
    options!(opts)
    raw().exists?(Query.scope(query), opts)
  end

  def aggregate(query, aggregate, opts) when is_list(opts),
    do: aggregate(query, aggregate, :id, opts)

  def aggregate(query, aggregate, field), do: aggregate(query, aggregate, field, [])
  def aggregate(query, aggregate), do: aggregate(query, aggregate, :id, [])

  def aggregate(query, aggregate, field, opts) do
    options!(opts)
    raw().aggregate(Query.scope(query), aggregate, field, opts)
  end

  def preload(records, preloads, opts \\ []), do: Preloader.load(records, preloads, opts)

  for action <- [:insert, :update, :delete] do
    def unquote(action)(record, opts \\ []) do
      cs = Writes.prepare(record, unquote(action))
      opts = Writes.options!(cs.data.__struct__, opts)
      apply(raw(), unquote(action), [cs, opts])
    end

    def unquote(:"#{action}!")(record, opts \\ []) do
      case unquote(action)(record, opts) do
        {:ok, value} -> value
        {:error, cs} -> raise Ecto.InvalidChangesetError, action: unquote(action), changeset: cs
      end
    end
  end

  def insert_or_update(%Ecto.Changeset{data: %{__meta__: %{state: :built}}} = cs, opts),
    do: insert(cs, opts)

  def insert_or_update(cs, opts), do: update(cs, opts)
  def insert_or_update(cs), do: insert_or_update(cs, [])

  def insert_all(source, rows, opts \\ []) do
    raw().insert_all(source, Writes.rows!(source, rows), Writes.options!(source, opts))
  end

  def update_all(query, updates, opts \\ []) do
    options!(opts)
    Writes.validate_bulk!(query, updates)
    raw().update_all(Query.scope(query), updates, opts)
  end

  def delete_all(query, opts \\ []) do
    options!(opts)
    raw().delete_all(Query.scope(query), opts)
  end

  def transaction(fun_or_multi, opts \\ []) do
    Tenancy.current_id!()
    options!(opts)

    case fun_or_multi do
      %Ecto.Multi{} = multi -> raw().transaction(scope_multi(multi), opts)
      fun when is_function(fun, 0) -> raw().transaction(fun, opts)
      fun when is_function(fun, 1) -> raw().transaction(fn -> fun.(__MODULE__) end, opts)
    end
  end

  def rollback(value), do: raw().rollback(value)
  def in_transaction?, do: raw().in_transaction?()

  defp scope_multi(multi) do
    Enum.reduce(Ecto.Multi.to_list(multi), Ecto.Multi.new(), fn
      {:merge, {:merge, fun}}, acc ->
        Ecto.Multi.merge(acc, fn changes -> fun |> call_merge(changes) |> scope_multi() end)

      {name, {:run, fun}}, acc ->
        Ecto.Multi.run(acc, name, fn _, changes -> call_run(fun, changes) end)

      {name, {:put, value}}, acc ->
        Ecto.Multi.put(acc, name, value)

      {name, {action, cs, opts}}, acc when action in [:insert, :update, :delete] ->
        Ecto.Multi.run(acc, name, fn _, _ -> apply(__MODULE__, action, [cs, opts]) end)

      {name, {:insert_all, source, rows, opts}}, acc ->
        Ecto.Multi.run(acc, name, fn _, _ -> {:ok, insert_all(source, rows, opts)} end)

      {name, {:delete_all, query, opts}}, acc ->
        Ecto.Multi.run(acc, name, fn _, _ -> {:ok, delete_all(query, opts)} end)

      {name, {:update_all, query, updates, opts}}, acc ->
        Ecto.Multi.run(acc, name, fn _, _ -> {:ok, update_all(query, updates, opts)} end)

      {name, {:error, value}}, acc ->
        Ecto.Multi.error(acc, name, value)

      _, _ ->
        Tenancy.deny!()
    end)
  end

  defp call_merge({mod, fun, args}, changes), do: apply(mod, fun, [changes | args])
  defp call_merge(fun, changes), do: fun.(changes)
  defp call_run({mod, fun, args}, changes), do: apply(mod, fun, [__MODULE__, changes | args])
  defp call_run(fun, changes), do: fun.(__MODULE__, changes)
  defp options!(opts), do: if(Keyword.has_key?(opts, :prefix), do: Tenancy.deny!())
  defp raw, do: Escalated.storage_repo()
end
