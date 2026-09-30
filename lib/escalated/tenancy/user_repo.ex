defmodule Escalated.Tenancy.UserRepo do
  @moduledoc false
  import Ecto.Query
  alias Escalated.Tenancy

  def all(query, opts \\ []), do: raw().all(scope(query), opts)
  def one(query, opts \\ []), do: raw().one(scope(query), opts)
  def exists?(query, opts \\ []), do: raw().exists?(scope(query), opts)
  def aggregate(query, kind, field), do: raw().aggregate(scope(query), kind, field)
  def get(query, id, opts \\ []), do: one(where(query, [u], u.id == ^id), opts)
  def get_by(query, clauses, opts \\ []), do: one(where(query, ^clauses), opts)

  def get!(query, id, opts \\ []) do
    get(query, id, opts) || raise Ecto.NoResultsError, queryable: query
  end

  def update(_changeset, _opts \\ []), do: Tenancy.deny!()
  def insert(_changeset, _opts \\ []), do: Tenancy.deny!()
  def delete(_changeset, _opts \\ []), do: Tenancy.deny!()

  defp scope(query) do
    query = Ecto.Queryable.to_query(query)

    if query.from.source != {Escalated.user_schema().__schema__(:source), Escalated.user_schema()} do
      Tenancy.deny!()
    end

    Tenancy.scope_users(query)
  end

  defp raw, do: Escalated.config(:user_repo) || Escalated.storage_repo()
end
