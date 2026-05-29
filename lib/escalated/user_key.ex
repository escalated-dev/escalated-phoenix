defmodule Escalated.UserKey do
  @moduledoc """
  Resolves the column/field type Escalated uses to store references to the host
  app's users, so UUID/string-keyed hosts work alongside integer-keyed ones.

  Configure with `config :escalated, user_key_type: :integer | :binary_id | :string`.
  Default `:integer` preserves existing behavior.
  """

  @doc "Ecto migration column type for a host user id."
  def migration_type do
    case type() do
      :binary_id -> :binary_id
      :string -> :string
      _ -> :integer
    end
  end

  @doc "Ecto schema field type for a host user id."
  def field_type do
    case type() do
      :binary_id -> :binary_id
      :string -> :string
      _ -> :integer
    end
  end

  defp type, do: Application.get_env(:escalated, :user_key_type, :integer)
end
