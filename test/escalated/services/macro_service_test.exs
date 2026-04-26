defmodule Escalated.Services.MacroServiceTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.Macro

  describe "changeset" do
    test "casts allowed fields and validates required name" do
      cs =
        Macro.changeset(%Macro{}, %{
          name: "Close + reply",
          actions: [%{"type" => "change_status", "value" => "resolved"}],
          is_shared: true,
          created_by: 42
        })

      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :name) == "Close + reply"
      assert Ecto.Changeset.get_field(cs, :is_shared) == true
      assert Ecto.Changeset.get_field(cs, :created_by) == 42
    end

    test "rejects when name is missing" do
      cs = Macro.changeset(%Macro{}, %{actions: []})
      refute cs.valid?
    end
  end

  describe "for_agent/2 query" do
    test "filters to shared macros plus agent's own" do
      query = Macro |> Macro.for_agent(42)
      ecto_str = inspect(query)
      assert ecto_str =~ "is_shared == true"
      assert ecto_str =~ "created_by == ^42"
    end
  end

  describe "to_json/1" do
    test "shapes the row for the agent / admin frontend" do
      m = %Macro{
        id: 7,
        name: "Close + reply",
        actions: [%{"type" => "change_status", "value" => "resolved"}],
        is_shared: true,
        created_by: 42
      }

      json = Macro.to_json(m)
      assert json.id == 7
      assert json.name == "Close + reply"
      assert json.is_shared == true
      assert json.created_by == 42
      assert is_list(json.actions)
    end
  end
end
