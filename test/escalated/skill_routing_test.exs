defmodule Escalated.SkillRoutingTest do
  use ExUnit.Case, async: true

  alias Escalated.SkillRouting

  describe "SkillRouting module" do
    test "find_matching_agents/1 is defined" do
      assert function_exported?(SkillRouting, :find_matching_agents, 1)
    end
  end
end
