defmodule Escalated.Services.AutomationRunnerTest do
  use ExUnit.Case, async: true

  alias Escalated.Services.AutomationRunner
  alias Escalated.Schemas.Automation

  # The runner is repo-driven; we use a simple in-memory mock repo to
  # exercise it without an actual database. Each test passes its own
  # repo module so they don't leak state across tests.

  describe "active scope" do
    test "returns active automations ordered by position then id" do
      query = Automation |> Automation.active()
      ecto_query_str = inspect(query)
      assert ecto_query_str =~ "active == true"
      assert ecto_query_str =~ "order_by"
    end
  end

  describe "changeset" do
    test "casts allowed fields and validates required name" do
      cs =
        Automation.changeset(%Automation{}, %{
          name: "close-stale",
          conditions: [%{"field" => "hours_since_created", "operator" => ">", "value" => 48}],
          actions: [%{"type" => "change_status", "value" => "closed"}]
        })

      assert cs.valid?
      assert get_field_in(cs, :name) == "close-stale"
      assert length(get_field_in(cs, :actions)) == 1
    end

    test "rejects when name is missing" do
      cs = Automation.changeset(%Automation{}, %{conditions: [], actions: []})
      refute cs.valid?
      assert {:name, _} = Enum.find(cs.errors, fn {f, _} -> f == :name end)
    end
  end

  describe "to_json/1" do
    test "shapes the row for the admin frontend" do
      a = %Automation{
        id: 7,
        name: "auto-close",
        description: "after 48h",
        conditions: [%{"field" => "hours_since_created", "operator" => ">", "value" => 48}],
        actions: [%{"type" => "change_status", "value" => "closed"}],
        active: true,
        position: 3,
        last_run_at: nil
      }

      json = Automation.to_json(a)
      assert json.id == 7
      assert json.name == "auto-close"
      assert json.active == true
      assert json.position == 3
      assert json.last_run_at == nil
      assert is_list(json.actions)
      assert is_list(json.conditions)
    end
  end

  describe "run/1 with a stub repo" do
    defmodule StubRepo do
      def all(_query), do: []
      def get_by(_schema, _opts), do: nil
      def insert(_changeset), do: {:ok, nil}
      def update(_changeset), do: {:ok, nil}
      def insert_all(_table, _rows, _opts), do: {0, nil}
    end

    test "returns 0 when there are no active automations" do
      assert AutomationRunner.run(StubRepo) == 0
    end
  end

  defp get_field_in(%Ecto.Changeset{} = cs, field) do
    Ecto.Changeset.get_field(cs, field)
  end
end
