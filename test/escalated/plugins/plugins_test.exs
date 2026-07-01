defmodule Escalated.PluginsTest do
  use Escalated.DataCase, async: false

  alias Escalated.Plugins
  alias Escalated.Plugins.Hooks

  defmodule ActivePlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "active-plugin"

    @impl true
    def name, do: "Active Plugin"

    @impl true
    def handle_action("ticket_created", [ticket]) do
      notify({:action, "ticket_created", ticket})
    end

    def handle_action(hook, _args), do: notify({:action, hook})

    @impl true
    def handle_filter("ticket_subject", value, _args), do: value <> " [active]"
    def handle_filter(_hook, value, _args), do: value

    @impl true
    def on_activate, do: notify(:on_activate)

    @impl true
    def on_deactivate, do: notify(:on_deactivate)

    defp notify(message) do
      case Application.get_env(:escalated, :test_pid) do
        pid when is_pid(pid) -> send(pid, message)
        _ -> :ok
      end
    end
  end

  defmodule RaisingPlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "raising-plugin"

    @impl true
    def handle_action(_hook, _args), do: raise("boom")

    @impl true
    def handle_filter(_hook, _value, _args), do: raise("boom")
  end

  setup do
    saved = %{
      plugins: Application.get_env(:escalated, :plugins),
      hooks: Application.get_env(:escalated, :hooks),
      filters: Application.get_env(:escalated, :filters),
      test_pid: Application.get_env(:escalated, :test_pid)
    }

    Application.put_env(:escalated, :plugins, [ActivePlugin, RaisingPlugin])
    Application.put_env(:escalated, :test_pid, self())

    on_exit(fn -> Enum.each(saved, fn {key, value} -> restore(key, value) end) end)
    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:escalated, key)
  defp restore(key, value), do: Application.put_env(:escalated, key, value)

  describe "all/0" do
    test "lists registered plugins with activation state and manifest" do
      {:ok, _} = Plugins.activate("active-plugin")

      all = Plugins.all()
      active = Enum.find(all, &(&1.slug == "active-plugin"))
      raising = Enum.find(all, &(&1.slug == "raising-plugin"))

      assert active.is_active
      assert active.name == "Active Plugin"
      refute raising.is_active
      # Falls back to a humanized slug when name/0 is not implemented.
      assert raising.name == "Raising Plugin"
    end
  end

  describe "activate/1" do
    test "persists an active row, runs on_activate, and fires plugin_activated" do
      assert {:ok, plugin} = Plugins.activate("active-plugin")
      assert plugin.is_active
      assert plugin.activated_at

      assert_received :on_activate
      assert_received {:action, "plugin_activated"}
      assert_received {:action, "plugin_activated_active-plugin"}
    end

    test "reactivates an existing row" do
      {:ok, _} = Plugins.activate("active-plugin")
      {:ok, _} = Plugins.deactivate("active-plugin")
      assert {:ok, plugin} = Plugins.activate("active-plugin")
      assert plugin.is_active
      assert length(Plugins.activated_slugs()) == 1
    end
  end

  describe "active_plugins/0" do
    test "reflects DB activation state" do
      assert Plugins.active_plugins() == []
      {:ok, _} = Plugins.activate("active-plugin")
      assert Plugins.active_plugins() == [ActivePlugin]
    end
  end

  describe "deactivate/1" do
    test "flips the row inactive and fires plugin_deactivated" do
      {:ok, _} = Plugins.activate("active-plugin")

      assert {:ok, plugin} = Plugins.deactivate("active-plugin")
      refute plugin.is_active
      assert plugin.deactivated_at

      assert_received {:action, "plugin_deactivated"}
      assert_received :on_deactivate
      assert Plugins.active_plugins() == []
    end

    test "returns an error for an unknown slug" do
      assert {:error, :not_found} = Plugins.deactivate("nope")
    end
  end

  describe "delete/1" do
    test "removes the activation row after firing plugin_uninstalling" do
      {:ok, _} = Plugins.activate("active-plugin")

      assert {:ok, _} = Plugins.delete("active-plugin")
      assert Plugins.activated_slugs() == []
      assert_received {:action, "plugin_uninstalling"}
    end

    test "returns an error for an unknown slug" do
      assert {:error, :not_found} = Plugins.delete("nope")
    end
  end

  describe "Hooks.do_action/2" do
    test "dispatches only to active plugins" do
      Hooks.do_action("ticket_created", [%{id: 1}])
      refute_received {:action, "ticket_created", _}

      {:ok, _} = Plugins.activate("active-plugin")
      Hooks.do_action("ticket_created", [%{id: 2}])
      assert_received {:action, "ticket_created", %{id: 2}}
    end

    test "swallows a raising handler" do
      {:ok, _} = Plugins.activate("raising-plugin")
      assert Hooks.do_action("anything", []) == :ok
    end

    test "fires config-registered action callbacks" do
      pid = self()
      callback = fn arg -> send(pid, {:cfg, arg}) end
      Application.put_env(:escalated, :hooks, %{"custom" => [callback]})

      Hooks.do_action("custom", ["payload"])
      assert_received {:cfg, "payload"}
    end
  end

  describe "Hooks.apply_filters/3" do
    test "is the identity function with no handlers" do
      assert Hooks.apply_filters("noop", "value") == "value"
    end

    test "threads the value through config filters then plugin filters" do
      filter = fn value -> value <> " [cfg]" end
      Application.put_env(:escalated, :filters, %{"ticket_subject" => [filter]})
      {:ok, _} = Plugins.activate("active-plugin")

      assert Hooks.apply_filters("ticket_subject", "Subject") == "Subject [cfg] [active]"
    end

    test "falls back to the running value when a filter raises" do
      {:ok, _} = Plugins.activate("raising-plugin")
      assert Hooks.apply_filters("ticket_subject", "Subject") == "Subject"
    end
  end
end
