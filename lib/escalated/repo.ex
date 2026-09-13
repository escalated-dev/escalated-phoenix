defmodule Escalated.Repo do
  @moduledoc """
  Convenience module that proxies to the host application's configured Ecto repo.

  All Escalated database operations use `Escalated.repo()` directly, but this
  module provides a namespace for any Escalated-specific query helpers.
  """

  @doc """
  Returns the configured Ecto repo module.
  """
  def repo, do: Escalated.repo()

  @doc """
  Insert options that skip a row duplicating the unique index on
  `conflict_target`: `on_conflict: :nothing` plus that target.

  MySQL cannot name a conflict target -- its `ON DUPLICATE KEY` applies to every
  unique key on the table, and Ecto raises if one is given -- so there the
  target is left out. Use it only on a table whose one unique index, besides
  the primary key, is `conflict_target`, so both spellings mean the same thing.
  """
  def ignore_duplicates(conflict_target) do
    if Escalated.repo().__adapter__() == Ecto.Adapters.MyXQL do
      [on_conflict: :nothing]
    else
      [on_conflict: :nothing, conflict_target: conflict_target]
    end
  end

  @doc """
  Paginate a query with limit/offset.

  Returns `{entries, %{total: count, page: page, per_page: per_page}}`.
  """
  def paginate(query, opts \\ []) do
    repo = Escalated.repo()
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 25)

    import Ecto.Query

    total = repo.aggregate(query, :count)

    entries =
      query
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> repo.all()

    {entries, %{total: total, page: page, per_page: per_page}}
  end
end
