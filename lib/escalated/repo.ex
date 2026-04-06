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
