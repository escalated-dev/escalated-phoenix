defmodule Escalated.Migration do
  @moduledoc """
  Column definitions for Escalated's migrations that databases spell
  differently.

  Several tables store a list: workflow and macro actions, webhook events, chat
  routing agent ids, custom field options and two-factor recovery codes.
  PostgreSQL has array columns. SQLite stores Ecto's array type as JSON text.
  MySQL has neither, and Ecto refuses to create an array column on it.

  The migrations call these functions instead of naming `{:array, inner}`
  directly. On PostgreSQL and SQLite they return exactly what the migrations
  always declared, so an existing install's schema is unchanged; on MySQL the
  column is JSON. The schemas keep `{:array, inner}` everywhere -- Ecto's MySQL
  adapter reads a list back out of a JSON column and writes one into it.
  """

  @doc """
  The column type for a list of `inner`: `{:array, inner}`, or `:json` on MySQL.
  """
  def list_type(inner) do
    if mysql?(), do: :json, else: {:array, inner}
  end

  @doc """
  The `default:` for an empty list column: `[]`, or on MySQL the expression
  `('[]')` -- MySQL only accepts a default for a JSON column as an expression.
  """
  def empty_list do
    if mysql?(), do: {:fragment, "('[]')"}, else: []
  end

  # The repo the running migration targets. Compared by name, so a host without
  # the MySQL adapter installed never needs the module loaded.
  defp mysql? do
    Ecto.Migration.repo().__adapter__() == Ecto.Adapters.MyXQL
  end
end
