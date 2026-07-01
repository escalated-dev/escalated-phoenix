defmodule Escalated.Plugins.Hooks do
  @moduledoc """
  WordPress-style action/filter dispatch, the core of the extensibility layer.

  Two kinds of hook, mirroring the Laravel `HookManager`:

    * **Actions** fire side effects. `do_action/2` invokes every registered
      handler and ignores their return values.
    * **Filters** transform a value. `apply_filters/3` threads the value through
      every registered handler; each returns the next value.

  Handlers come from two sources, run in this order:

    1. **Host callbacks** declared in config — the lightweight equivalent of
       `escalated_add_action` / `escalated_add_filter`:

           config :escalated,
             hooks: %{"ticket_created" => [&MyApp.on_ticket_created/1]},
             filters: %{"ticket_display_subject" => [&MyApp.decorate_subject/2]}

       Action callbacks are applied to the hook args; filter callbacks receive
       the running value followed by the hook args and return the new value.

    2. **Active plugin modules** (`Escalated.Plugins.Plugin`) that export
       `handle_action/2` / `handle_filter/3`. Only activated plugins are
       dispatched to.

  Every handler is wrapped so a raising handler is logged and skipped: an action
  error is swallowed, a filter error falls back to the pre-handler value. A bad
  plugin can never crash the host request.
  """
  require Logger

  alias Escalated.Plugins

  @doc """
  Fires an action hook, invoking every registered handler for its side effects.
  Always returns `:ok`.
  """
  def do_action(hook, args \\ []) when is_binary(hook) do
    args = List.wrap(args)

    Enum.each(config_callbacks(:hooks, hook), fn callback ->
      run_action(hook, fn -> apply(callback, args) end)
    end)

    Enum.each(action_plugins(), fn module ->
      run_action(hook, fn -> module.handle_action(hook, args) end)
    end)

    :ok
  end

  @doc """
  Applies a filter hook, threading `value` through every registered handler and
  returning the final (possibly modified) value.
  """
  def apply_filters(hook, value, args \\ []) when is_binary(hook) do
    args = List.wrap(args)

    value =
      Enum.reduce(config_callbacks(:filters, hook), value, fn callback, acc ->
        run_filter(hook, acc, fn -> apply(callback, [acc | args]) end)
      end)

    Enum.reduce(filter_plugins(), value, fn module, acc ->
      run_filter(hook, acc, fn -> module.handle_filter(hook, acc, args) end)
    end)
  end

  defp config_callbacks(key, hook) do
    config = Escalated.config(key, %{})

    config
    |> Map.get(hook, [])
    |> List.wrap()
  end

  defp action_plugins do
    Enum.filter(Plugins.active_plugins(), &function_exported?(&1, :handle_action, 2))
  end

  defp filter_plugins do
    Enum.filter(Plugins.active_plugins(), &function_exported?(&1, :handle_filter, 3))
  end

  defp run_action(hook, fun) do
    fun.()
    :ok
  rescue
    error ->
      Logger.error("Escalated action hook #{hook} raised: #{Exception.message(error)}")
      :ok
  end

  defp run_filter(hook, previous, fun) do
    fun.()
  rescue
    error ->
      Logger.error("Escalated filter hook #{hook} raised: #{Exception.message(error)}")
      previous
  end
end
