defmodule Escalated.Plugins.Plugin do
  @moduledoc """
  Behaviour a host-application plugin module implements.

  Because Escalated runs on the BEAM, plugins are ordinary Elixir modules the
  host compiles and registers in config — there is no runtime file upload or
  subprocess bridge (the Laravel reference supports both because PHP can
  `require` uploaded files and shell out to a Node runtime; neither translates
  to a compiled release). The host registers its plugins with:

      config :escalated, plugins: [MyApp.Plugins.Billing, MyApp.Plugins.Analytics]

  An admin activates/deactivates a registered plugin by its `slug/0`
  (persisted in the `escalated_plugins` table). Only *active* plugins receive
  hook dispatch from `Escalated.Plugins.Hooks`.

  Only `slug/0` is required. A minimal plugin:

      defmodule MyApp.Plugins.Billing do
        @behaviour Escalated.Plugins.Plugin

        @impl true
        def slug, do: "billing"

        @impl true
        def handle_action("ticket_created", [ticket]) do
          MyApp.Billing.track(ticket)
        end

        def handle_action(_hook, _args), do: :ok
      end

  ## Actions vs filters

    * `handle_action/2` — invoked for side effects when `do_action/2` fires;
      its return value is ignored.
    * `handle_filter/3` — invoked when `apply_filters/3` fires; it receives the
      running value and MUST return the (possibly modified) value.

  ## Lifecycle

    * `on_activate/0` — runs when the plugin is activated.
    * `on_deactivate/0` — runs when the plugin is deactivated.
  """

  @doc "Unique, stable identifier used as the DB slug and hook suffix."
  @callback slug() :: String.t()

  @doc "Human-readable name for the admin UI (defaults to a humanized slug)."
  @callback name() :: String.t()

  @doc "Semantic version string (defaults to \"1.0.0\")."
  @callback version() :: String.t()

  @doc "Short description for the admin UI."
  @callback description() :: String.t()

  @doc "Handle a fired action hook. Return value is ignored."
  @callback handle_action(hook :: String.t(), args :: list()) :: any()

  @doc "Transform a value for a filter hook. MUST return the new value."
  @callback handle_filter(hook :: String.t(), value :: any(), args :: list()) :: any()

  @doc "Called when the plugin is activated."
  @callback on_activate() :: any()

  @doc "Called when the plugin is deactivated."
  @callback on_deactivate() :: any()

  @optional_callbacks name: 0,
                      version: 0,
                      description: 0,
                      handle_action: 2,
                      handle_filter: 3,
                      on_activate: 0,
                      on_deactivate: 0
end
