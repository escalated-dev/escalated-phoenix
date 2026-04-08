defmodule Escalated.Controllers.WidgetControllerTest do
  use ExUnit.Case, async: true

  alias Escalated.Controllers.WidgetController
  alias Escalated.Plugs.WidgetRateLimit

  describe "WidgetController module" do
    test "module is defined" do
      assert Code.ensure_loaded?(WidgetController)
    end

    test "config/2 is defined" do
      assert function_exported?(WidgetController, :config, 2)
    end

    test "create_ticket/2 is defined" do
      assert function_exported?(WidgetController, :create_ticket, 2)
    end

    test "show_ticket/2 is defined" do
      assert function_exported?(WidgetController, :show_ticket, 2)
    end

    test "reply/2 is defined" do
      assert function_exported?(WidgetController, :reply, 2)
    end
  end

  describe "WidgetRateLimit plug" do
    test "module is defined" do
      assert Code.ensure_loaded?(WidgetRateLimit)
    end

    test "implements Plug behaviour (init/1)" do
      assert function_exported?(WidgetRateLimit, :init, 1)
    end

    test "implements Plug behaviour (call/2)" do
      assert function_exported?(WidgetRateLimit, :call, 2)
    end

    test "init returns opts unchanged" do
      opts = [max_requests: 10]
      assert WidgetRateLimit.init(opts) == opts
    end
  end

  describe "widget settings defaults" do
    test "widget_settings config key returns map or nil" do
      result = Escalated.config(:widget_settings, %{})
      assert is_map(result)
    end

    test "widget_rate_limit config key returns map or nil" do
      result = Escalated.config(:widget_rate_limit, %{})
      assert is_map(result)
    end
  end
end
