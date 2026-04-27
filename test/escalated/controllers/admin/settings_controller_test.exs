defmodule Escalated.Controllers.Admin.SettingsControllerTest do
  use ExUnit.Case, async: true

  alias Escalated.Controllers.Admin.SettingsController
  alias Escalated.Schemas.EscalatedSetting
  alias Escalated.Services.SettingsService

  # Pure-function / module-interface tests. Full end-to-end validation
  # runs through the consuming router + repo once a test repo is
  # configured — same philosophy as the WorkflowExecutor test file.

  describe "SettingsController module" do
    test "module is defined" do
      assert Code.ensure_loaded?(SettingsController)
    end

    test "index/2 is defined" do
      assert function_exported?(SettingsController, :index, 2)
    end

    test "update/2 is defined" do
      assert function_exported?(SettingsController, :update, 2)
    end

    test "public_tickets/2 is defined" do
      assert function_exported?(SettingsController, :public_tickets, 2)
    end

    test "update_public_tickets/2 is defined" do
      assert function_exported?(SettingsController, :update_public_tickets, 2)
    end
  end

  describe "parse_positive_int/1" do
    test "nil returns nil" do
      assert SettingsController.parse_positive_int(nil) == nil
    end

    test "empty string returns nil" do
      assert SettingsController.parse_positive_int("") == nil
    end

    test "positive integer returns itself" do
      assert SettingsController.parse_positive_int(42) == 42
    end

    test "zero returns nil" do
      assert SettingsController.parse_positive_int(0) == nil
    end

    test "negative integer returns nil" do
      assert SettingsController.parse_positive_int(-5) == nil
    end

    test "numeric string returns parsed integer" do
      assert SettingsController.parse_positive_int("99") == 99
    end

    test "zero string returns nil" do
      assert SettingsController.parse_positive_int("0") == nil
    end

    test "non-numeric string returns nil" do
      assert SettingsController.parse_positive_int("abc") == nil
    end

    test "trailing-garbage string returns nil" do
      assert SettingsController.parse_positive_int("42x") == nil
    end

    test "unknown types return nil" do
      assert SettingsController.parse_positive_int(%{}) == nil
      assert SettingsController.parse_positive_int([]) == nil
      assert SettingsController.parse_positive_int(true) == nil
    end
  end

  describe "SettingsService module" do
    test "module is defined" do
      assert Code.ensure_loaded?(SettingsService)
    end

    test "get/1 is defined" do
      assert function_exported?(SettingsService, :get, 1)
    end

    test "get_or_default/2 is defined" do
      assert function_exported?(SettingsService, :get_or_default, 2)
    end

    test "set/3 is defined (set/2 via default arg)" do
      assert function_exported?(SettingsService, :set, 3)
    end

    test "delete/1 is defined" do
      assert function_exported?(SettingsService, :delete, 1)
    end
  end

  describe "EscalatedSetting schema" do
    test "module is defined" do
      assert Code.ensure_loaded?(EscalatedSetting)
    end

    test "changeset requires a key" do
      cs = EscalatedSetting.changeset(%EscalatedSetting{}, %{value: "v", group: "g"})
      refute cs.valid?
      assert {"can't be blank", _} = cs.errors[:key]
    end

    test "changeset is valid with just a key" do
      cs = EscalatedSetting.changeset(%EscalatedSetting{}, %{key: "k"})
      assert cs.valid?
    end

    test "changeset accepts value + group" do
      cs =
        EscalatedSetting.changeset(%EscalatedSetting{}, %{
          key: "guest_policy_mode",
          value: "guest_user",
          group: "public_tickets"
        })

      assert cs.valid?
    end
  end
end
