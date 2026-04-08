defmodule Escalated.Plugs.EnsureKbEnabledTest do
  use ExUnit.Case, async: true

  alias Escalated.Plugs.EnsureKbEnabled
  alias Escalated.Config

  describe "EnsureKbEnabled plug" do
    test "module is defined" do
      assert Code.ensure_loaded?(EnsureKbEnabled)
    end

    test "implements Plug behaviour (init/1)" do
      assert function_exported?(EnsureKbEnabled, :init, 1)
    end

    test "implements Plug behaviour (call/2)" do
      assert function_exported?(EnsureKbEnabled, :call, 2)
    end

    test "init returns opts unchanged" do
      assert EnsureKbEnabled.init([]) == []
    end
  end

  describe "Config knowledge base helpers" do
    test "knowledge_base_enabled?/1 returns false by default" do
      config = %Config{}
      refute Config.knowledge_base_enabled?(config)
    end

    test "knowledge_base_enabled?/1 returns true when enabled" do
      config = %Config{knowledge_base_enabled: true}
      assert Config.knowledge_base_enabled?(config)
    end

    test "knowledge_base_public?/1 returns false by default" do
      config = %Config{}
      refute Config.knowledge_base_public?(config)
    end

    test "knowledge_base_public?/1 returns true when set" do
      config = %Config{knowledge_base_public: true}
      assert Config.knowledge_base_public?(config)
    end

    test "knowledge_base_feedback_enabled?/1 returns false by default" do
      config = %Config{}
      refute Config.knowledge_base_feedback_enabled?(config)
    end

    test "knowledge_base_feedback_enabled?/1 returns true when set" do
      config = %Config{knowledge_base_feedback_enabled: true}
      assert Config.knowledge_base_feedback_enabled?(config)
    end
  end

  describe "Config struct includes KB fields" do
    test "knowledge_base_enabled field exists with default false" do
      config = %Config{}
      assert config.knowledge_base_enabled == false
    end

    test "knowledge_base_public field exists with default false" do
      config = %Config{}
      assert config.knowledge_base_public == false
    end

    test "knowledge_base_feedback_enabled field exists with default false" do
      config = %Config{}
      assert config.knowledge_base_feedback_enabled == false
    end
  end
end
