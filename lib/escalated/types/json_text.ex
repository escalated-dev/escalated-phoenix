defmodule Escalated.Types.JsonText do
  @moduledoc """
  Any JSON value (a list or a map) kept in a text column.

  Ecto's `:map` type only takes maps, and the `{:array, _}` types are spelled
  differently per database. A text column holding the encoded value reads and
  writes the same way on SQLite, PostgreSQL and MySQL.
  """
  use Ecto.Type

  @impl true
  def type, do: :string

  @impl true
  def cast(value) when is_list(value) or is_map(value), do: {:ok, value}
  def cast(nil), do: {:ok, nil}

  def cast(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) or is_map(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  def cast(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} -> {:ok, decoded}
      _ -> {:ok, nil}
    end
  end

  def load(value) when is_list(value) or is_map(value), do: {:ok, value}
  def load(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}
  def dump(value) when is_list(value) or is_map(value), do: {:ok, Jason.encode!(value)}
  def dump(_), do: :error
end
