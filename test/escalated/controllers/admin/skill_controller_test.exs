defmodule Escalated.Controllers.Admin.SkillControllerTest do
  use ExUnit.Case, async: true

  alias Escalated.Controllers.Admin.SkillController

  describe "SkillController module" do
    test "module is defined" do
      assert Code.ensure_loaded?(SkillController)
    end

    test "defines six CRUD actions" do
      assert function_exported?(SkillController, :index, 2)
      assert function_exported?(SkillController, :new, 2)
      assert function_exported?(SkillController, :create, 2)
      assert function_exported?(SkillController, :edit, 2)
      assert function_exported?(SkillController, :update, 2)
      assert function_exported?(SkillController, :delete, 2)
    end
  end
end
