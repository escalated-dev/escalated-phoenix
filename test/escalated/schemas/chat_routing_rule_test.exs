defmodule Escalated.Schemas.ChatRoutingRuleTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.ChatRoutingRule

  describe "changeset/2" do
    test "valid changeset with name" do
      changeset = ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Default"})
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = ChatRoutingRule.changeset(%ChatRoutingRule{}, %{})
      refute changeset.valid?
      assert {:name, _} = hd(changeset.errors)
    end

    test "validates strategy inclusion" do
      changeset = ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Test", strategy: "invalid"})
      refute changeset.valid?
    end

    test "accepts valid strategies" do
      for strategy <- ~w(round_robin least_active department) do
        changeset = ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Test", strategy: strategy})
        assert changeset.valid?, "expected #{strategy} to be valid"
      end
    end

    test "validates max_concurrent_chats > 0" do
      changeset = ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Test", max_concurrent_chats: 0})
      refute changeset.valid?

      changeset = ChatRoutingRule.changeset(%ChatRoutingRule{}, %{name: "Test", max_concurrent_chats: 5})
      assert changeset.valid?
    end
  end

  describe "defaults" do
    test "default values" do
      rule = %ChatRoutingRule{}
      assert rule.strategy == "round_robin"
      assert rule.is_active == true
      assert rule.max_concurrent_chats == 5
      assert rule.priority == 0
      assert rule.agent_ids == []
    end
  end

  describe "strategies/0" do
    test "returns all valid strategies" do
      strategies = ChatRoutingRule.strategies()
      assert "round_robin" in strategies
      assert "least_active" in strategies
      assert "department" in strategies
    end
  end
end
