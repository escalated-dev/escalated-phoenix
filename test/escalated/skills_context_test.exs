defmodule Escalated.SkillsContextTest do
  use ExUnit.Case, async: true

  alias Escalated.Schemas.Skill
  alias Escalated.Skills

  describe "Skills module" do
    test "exports contract functions" do
      assert function_exported?(Skills, :list_for_admin, 0)
      assert function_exported?(Skills, :find_for_edit, 1)
      assert function_exported?(Skills, :form_context, 0)
      assert function_exported?(Skills, :create_skill, 1)
      assert function_exported?(Skills, :update_skill, 2)
      assert function_exported?(Skills, :delete_skill, 1)
    end
  end

  describe "Skill.changeset/2" do
    test "requires name" do
      cs = Skill.changeset(%Skill{}, %{})
      refute cs.valid?
      assert Keyword.has_key?(cs.errors, :name)
    end

    test "derives slug from name" do
      cs = Skill.changeset(%Skill{}, %{"name" => "Networking Basics"})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :slug) == "networking-basics"
    end
  end
end
