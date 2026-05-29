defmodule Escalated.UserKeyTest do
  use ExUnit.Case, async: true

  alias Escalated.UserKey

  test "default migration_type and field_type are :integer" do
    assert UserKey.migration_type() == :integer
    assert UserKey.field_type() == :integer
  end

  test "binary_id config returns :binary_id for migration_type and field_type" do
    prev = Application.get_env(:escalated, :user_key_type)

    on_exit(fn ->
      if prev == nil do
        Application.delete_env(:escalated, :user_key_type)
      else
        Application.put_env(:escalated, :user_key_type, prev)
      end
    end)

    Application.put_env(:escalated, :user_key_type, :binary_id)

    assert UserKey.migration_type() == :binary_id
    assert UserKey.field_type() == :binary_id
  end
end
