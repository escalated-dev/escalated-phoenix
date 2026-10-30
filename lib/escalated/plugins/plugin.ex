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

  ## Pages

  A plugin can add full admin pages, served by the shared
  `Escalated/Plugin/Page` screen (plugin contract, "Pages"). `pages/0`
  returns one map per page (atom or string keys):

    * `route` (required) — the URL below the plugin,
      `{prefix}/admin/plugins/{slug}/{route}`. Leading slashes are dropped and
      it may contain `/`.
    * `component` (required) — the Vue component the plugin's frontend
      package registered with `defineEscalatedPlugin`.
    * `title` — the page title (and the default menu label).
    * `layout` — `"admin"` by default.
    * `capability` — a permission slug the viewer must hold (403 without it).
      While roles & permissions is on it is checked against the user's roles;
      `config :escalated, plugin_capability_check: fn user, slug -> ... end`
      decides it instead when set. While roles & permissions is off and no
      check is configured, the admin gate alone decides.
    * `props` — static props for the component (`%{}` by default).
    * `menu` — `%{label, icon, position (100), section ("admin")}` lists the
      page in the shared `escalated.plugins.menuItems`. `admin` items go to
      admins only, and an item whose `capability` the viewer lacks is left
      out.

  An entry without a route or component is skipped with a warning. Only an
  **active** plugin's pages answer; anything else is a 404. Every page sits
  behind the admin guard.

  `page_props/2` receives the page's `component` and the signed-in user and
  returns the component's props (the native counterpart of an SDK plugin's
  `GET /{component}` endpoint). Returning `nil`, or not defining it, sends
  the page's static `props`; raising sends `%{}` and is logged.

      @impl true
      def pages do
        [
          %{
            route: "settings",
            component: "BillingSettings",
            title: "Billing",
            menu: %{label: "Billing", icon: "credit-card"}
          }
        ]
      end

      @impl true
      def page_props("BillingSettings", user), do: %{plan: MyApp.Billing.plan(user)}
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

  @doc "Admin pages the plugin adds; see \"Pages\" above."
  @callback pages() :: [map()]

  @doc "Props for one of the plugin's pages, by component, for the signed-in user."
  @callback page_props(component :: String.t(), user :: map() | nil) :: map() | nil

  @optional_callbacks name: 0,
                      version: 0,
                      description: 0,
                      handle_action: 2,
                      handle_filter: 3,
                      on_activate: 0,
                      on_deactivate: 0,
                      pages: 0,
                      page_props: 2
end
