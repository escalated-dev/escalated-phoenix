defmodule Escalated.Controllers.Admin.UserControllerTest do
  @moduledoc """
  Module-interface tests for `Escalated.Controllers.Admin.UserController`,
  mirroring the seven cases in escalated-laravel's
  `tests/Feature/Admin/UserControllerTest.php` (PR #94).

  Same philosophy as `settings_controller_test.exs`: the controller
  calls `Escalated.repo()` + `Escalated.user_schema()` on the success
  path, which needs a live Ecto repo. These tests cover the pure
  role-flip logic that encodes the behaviour and the module surface;
  end-to-end HTTP coverage runs in the host app's test suite (the
  reference NestJS, Laravel, etc. ports all have framework-level test
  harnesses for the same logic).
  """

  use ExUnit.Case, async: true

  alias Escalated.Controllers.Admin.UserController

  # Project-root-anchored paths so the "source contains X" assertions
  # don't depend on :code.priv_dir which may not exist before compile.
  # __DIR__ is .../test/escalated/controllers/admin, so go up 4 levels.
  @project_root Path.expand("../../../..", __DIR__)
  @router_path Path.join(@project_root, "lib/escalated/router.ex")
  @controller_path Path.join(@project_root, "lib/escalated/controllers/admin/user_controller.ex")

  describe "UserController module surface" do
    test "index/2 is defined" do
      assert function_exported?(UserController, :index, 2)
    end

    test "update_role/2 is defined" do
      assert function_exported?(UserController, :update_role, 2)
    end
  end

  # --- 1. Laravel: "lists users with their admin/agent flags for an admin"
  #     We can't hit the HTTP path without a repo, but we can verify
  #     the JSON payload shape an admin would see is exactly the four
  #     fields the frontend Index.vue expects.
  describe "user_to_payload/1 — list payload shape (Laravel: lists users)" do
    test "exposes id, name, email, is_admin, is_agent for an admin" do
      user = %{id: 1, name: "Admin", email: "admin@example.com", is_admin: true, is_agent: true}
      payload = UserController.user_to_payload(user)

      assert payload == %{
               id: 1,
               name: "Admin",
               email: "admin@example.com",
               is_admin: true,
               is_agent: true
             }
    end

    test "shows customer and agent rows alongside admins" do
      customer = UserController.user_to_payload(%{
        id: 2,
        name: "Customer",
        email: "customer@example.com",
        is_admin: false,
        is_agent: false
      })

      agent = UserController.user_to_payload(%{
        id: 3,
        name: "Agent",
        email: "agent@example.com",
        is_admin: false,
        is_agent: true
      })

      assert customer.is_admin == false
      assert customer.is_agent == false
      assert agent.is_admin == false
      assert agent.is_agent == true
    end

    test "coerces missing or nil flag columns to false" do
      payload = UserController.user_to_payload(%{id: 9, email: "x@y.test"})
      assert payload.is_admin == false
      assert payload.is_agent == false
      assert payload.name == nil
    end
  end

  # --- 2. Laravel: "blocks non-admins from the user list"
  #     The admin pipeline does this; we assert the controller is
  #     wired behind the EnsureAdmin plug via the router.
  describe "admin-only gating (Laravel: blocks non-admins)" do
    test "EnsureAdmin plug exists and is wired by the router for /admin/*" do
      assert Code.ensure_loaded?(Escalated.Plugs.EnsureAdmin)
      # The router pipes the entire /admin scope through EnsureAdmin
      # (see lib/escalated/router.ex), so user routes inherit it.
      router_source = File.read!(@router_path)

      assert router_source =~ "pipe_through Escalated.Plugs.EnsureAdmin"
      assert router_source =~ ~s("/users", UserController, :index)
      assert router_source =~ ~s("/users/:user_id/role", UserController, :update_role)
    end
  end

  # --- 3. Laravel: "promotes a user to admin via the panel"
  describe "build_updates/3 — admin promotion (Laravel: promotes a user to admin)" do
    test "role=admin, value=true sets both is_admin and is_agent" do
      target = %{id: 5, is_admin: false, is_agent: false}
      updates = UserController.build_updates("admin", true, target)

      assert Keyword.get(updates, :is_admin) == true
      assert Keyword.get(updates, :is_agent) == true
    end
  end

  # --- 4. Laravel: "promotes a user to agent only"
  describe "build_updates/3 — agent-only promotion (Laravel: promotes a user to agent only)" do
    test "role=agent, value=true sets is_agent without touching is_admin" do
      target = %{id: 5, is_admin: false, is_agent: false}
      updates = UserController.build_updates("agent", true, target)

      assert Keyword.get(updates, :is_agent) == true
      refute Keyword.has_key?(updates, :is_admin)
    end
  end

  # --- 5. Laravel: "prevents admins from demoting themselves"
  #     Pure logic exposed: the controller short-circuits before
  #     `build_updates` for self-admin-demotion. We assert the
  #     mapping for the role/value pair AND the controller-level
  #     guard by inspecting the source (similar self-check pattern
  #     to Laravel: $request->user()->getKey() === $target->getKey()).
  describe "self-demotion guard (Laravel: prevents admins from demoting themselves)" do
    test "controller source contains the self-target check" do
      source = File.read!(@controller_path)

      assert source =~ "self_target?"
      assert source =~ "You cannot remove your own admin role."
    end
  end

  # --- 6. Laravel: "demotes an admin and turns off agent in one step"
  #     -> Inverse: role=agent value=false on an admin target should
  #        flip BOTH is_agent and is_admin.
  describe "build_updates/3 — admin agent-revoke cascades (Laravel: demotes an admin and turns off agent)" do
    test "role=agent, value=false on an admin target also revokes admin" do
      target = %{id: 5, is_admin: true, is_agent: true}
      updates = UserController.build_updates("agent", false, target)

      assert Keyword.get(updates, :is_agent) == false
      assert Keyword.get(updates, :is_admin) == false
    end

    test "role=agent, value=false on a non-admin target leaves is_admin alone" do
      target = %{id: 5, is_admin: false, is_agent: true}
      updates = UserController.build_updates("agent", false, target)

      assert Keyword.get(updates, :is_agent) == false
      refute Keyword.has_key?(updates, :is_admin)
    end

    test "role=admin, value=false does NOT cascade to is_agent (ex-admins can still answer tickets)" do
      target = %{id: 5, is_admin: true, is_agent: true}
      updates = UserController.build_updates("admin", false, target)

      assert Keyword.get(updates, :is_admin) == false
      refute Keyword.has_key?(updates, :is_agent)
    end
  end

  # --- 7. Laravel: "filters users by search term"
  #     The Laravel controller globs email + name with `like %term%`.
  #     The Phoenix port uses ilike on the same two columns. We assert
  #     the controller source applies the same predicate.
  describe "search filter (Laravel: filters users by search term)" do
    test "controller searches both email and name with ilike" do
      source = File.read!(@controller_path)

      assert source =~ "ilike(u.email"
      assert source =~ "ilike(u.name"
    end
  end

  describe "validate_role/1" do
    test "accepts 'admin' and 'agent'" do
      assert UserController.validate_role("admin") == {:ok, "admin"}
      assert UserController.validate_role("agent") == {:ok, "agent"}
    end

    test "rejects anything else" do
      assert {:error, _} = UserController.validate_role("owner")
      assert {:error, _} = UserController.validate_role(nil)
      assert {:error, _} = UserController.validate_role("")
    end
  end

  describe "validate_value/1" do
    test "accepts booleans" do
      assert UserController.validate_value(true) == {:ok, true}
      assert UserController.validate_value(false) == {:ok, false}
    end

    test "accepts truthy/falsy strings and ints" do
      assert UserController.validate_value("true") == {:ok, true}
      assert UserController.validate_value("false") == {:ok, false}
      assert UserController.validate_value(1) == {:ok, true}
      assert UserController.validate_value(0) == {:ok, false}
    end

    test "rejects anything else" do
      assert {:error, _} = UserController.validate_value("yes")
      assert {:error, _} = UserController.validate_value(nil)
      assert {:error, _} = UserController.validate_value(2)
    end
  end
end
