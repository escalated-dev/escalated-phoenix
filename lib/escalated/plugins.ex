defmodule Escalated.Plugins do
  @moduledoc """
  Plugin registry and lifecycle management.

  Plugins are host-app modules implementing `Escalated.Plugins.Plugin`,
  registered via `config :escalated, plugins: [...]`. This module lists them,
  tracks activation state in the `escalated_plugins` table, and drives the
  activate / deactivate / uninstall lifecycle — firing the corresponding hooks
  through `Escalated.Plugins.Hooks` so plugins can react to their own state
  changes. Mirrors the Laravel `PluginService`.
  """
  require Logger

  alias Escalated.Permissions
  alias Escalated.Plugins.Hooks
  alias Escalated.Schemas.Plugin

  @doc """
  Returns every registered plugin as a manifest map merged with its current
  activation state, suitable for the admin UI.
  """
  def all do
    active = MapSet.new(activated_slugs())

    Enum.map(registered_modules(), fn module ->
      module
      |> manifest()
      |> Map.put(:is_active, MapSet.member?(active, module.slug()))
    end)
  end

  @doc "Returns the list of registered plugin modules (from config)."
  def registered_modules do
    # Plugin modules and lifecycle callbacks are platform-global host code.
    # Tenant-local activation rows do not make that code safe to execute.
    if Escalated.Tenancy.enabled?(), do: [], else: List.wrap(Escalated.config(:plugins, []))
  end

  @doc "Returns the slugs of all currently-activated plugins."
  def activated_slugs do
    repo = Escalated.repo()

    Plugin
    |> Plugin.active()
    |> repo.all()
    |> Enum.map(& &1.slug)
  end

  @doc """
  Returns the registered plugin modules that are currently active. Used by
  `Escalated.Plugins.Hooks` to decide which plugins receive dispatch.
  """
  def active_plugins do
    active = MapSet.new(activated_slugs())
    Enum.filter(registered_modules(), &MapSet.member?(active, &1.slug()))
  end

  @doc "Builds the manifest map for a registered plugin module."
  def manifest(module) do
    slug = module.slug()

    %{
      slug: slug,
      name: optional(module, :name, [], humanize(slug)),
      version: optional(module, :version, [], "1.0.0"),
      description: optional(module, :description, [], nil),
      module: inspect(module)
    }
  end

  @doc """
  Activates a plugin by slug: upserts its row as active, runs the plugin's
  `on_activate/0`, and fires the `plugin_activated` hooks.
  """
  def activate(slug) when is_binary(slug) do
    if Escalated.Tenancy.enabled?(),
      do: {:error, :tenant_mode_unsupported},
      else: do_activate(slug)
  end

  defp do_activate(slug) do
    repo = Escalated.repo()

    changeset =
      case repo.get_by(Plugin, slug: slug) do
        nil -> Plugin.changeset(%Plugin{}, %{slug: slug, is_active: true, activated_at: now()})
        row -> Plugin.changeset(row, %{is_active: true, activated_at: now(), deactivated_at: nil})
      end

    case repo.insert_or_update(changeset) do
      {:ok, plugin} ->
        run_lifecycle(slug, :on_activate)
        Hooks.do_action("plugin_activated", [slug])
        Hooks.do_action("plugin_activated_#{slug}", [])
        {:ok, plugin}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Deactivates a plugin by slug: fires the `plugin_deactivated` hooks (while the
  plugin is still active so it can react), runs `on_deactivate/0`, then marks
  the row inactive.
  """
  def deactivate(slug) when is_binary(slug) do
    if Escalated.Tenancy.enabled?(),
      do: {:error, :tenant_mode_unsupported},
      else: do_deactivate(slug)
  end

  defp do_deactivate(slug) do
    repo = Escalated.repo()

    case repo.get_by(Plugin, slug: slug) do
      nil ->
        {:error, :not_found}

      plugin ->
        Hooks.do_action("plugin_deactivated", [slug])
        Hooks.do_action("plugin_deactivated_#{slug}", [])
        run_lifecycle(slug, :on_deactivate)

        plugin
        |> Plugin.changeset(%{is_active: false, deactivated_at: now()})
        |> repo.update()
    end
  end

  @doc """
  Removes a plugin's activation record. Fires the `plugin_uninstalling` hooks
  first. The plugin's stored data (`Escalated.Plugins.Store`) is left intact.
  """
  def delete(slug) when is_binary(slug) do
    if Escalated.Tenancy.enabled?(), do: {:error, :tenant_mode_unsupported}, else: do_delete(slug)
  end

  defp do_delete(slug) do
    repo = Escalated.repo()

    case repo.get_by(Plugin, slug: slug) do
      nil ->
        {:error, :not_found}

      plugin ->
        Hooks.do_action("plugin_uninstalling", [slug])
        Hooks.do_action("plugin_uninstalling_#{slug}", [])
        run_lifecycle(slug, :on_deactivate)
        repo.delete(plugin)
    end
  end

  @doc """
  The pages a plugin module declares with its optional `pages/0`, normalized
  to `%{route, component, title, layout, capability, props, menu}`. Entries
  with an empty route or component are skipped with a warning.
  """
  def pages(module) do
    if function_exported?(module, :pages, 0) do
      module.pages()
      |> List.wrap()
      |> Enum.flat_map(&normalize_page(module, &1))
      |> Enum.uniq_by(& &1.route)
    else
      []
    end
  rescue
    error ->
      Logger.error(
        "Escalated plugin #{module.slug()} pages/0 raised: #{Exception.message(error)}"
      )

      []
  end

  @doc """
  Finds the page at `route` of the **active** plugin `slug`. Returns
  `{:ok, module, page}`, or `:error` for an unknown or inactive plugin or a
  route the plugin does not declare.
  """
  def find_page(slug, route) when is_binary(slug) and is_binary(route) do
    with module when not is_nil(module) <- Enum.find(active_plugins(), &(&1.slug() == slug)),
         page when not is_nil(page) <- Enum.find(pages(module), &(&1.route == route)) do
      {:ok, module, page}
    else
      _ -> :error
    end
  end

  @doc """
  The props for a page's component: the plugin's `page_props/2` answer, or the
  page's static `props` when it has none or answers `nil`. A raising
  `page_props/2` is logged and sends `%{}`.
  """
  def page_props(module, page, user) do
    answer =
      if function_exported?(module, :page_props, 2),
        do: module.page_props(page.component, user),
        else: nil

    if is_map(answer), do: answer, else: page.props
  rescue
    error ->
      Logger.error(
        "Escalated plugin #{module.slug()} page_props/2 raised for #{page.component}: " <>
          Exception.message(error)
      )

      %{}
  end

  @doc """
  Whether `user` holds a plugin page's `capability`; `nil` needs nothing. A
  configured `:plugin_capability_check` (`fn user, capability -> boolean end`)
  decides; otherwise `Escalated.Permissions.allows?/2` does (the user's roles
  while roles & permissions is on, the admin gate alone while it is off).
  """
  def capable?(_user, nil), do: true

  def capable?(user, capability) do
    case Escalated.config(:plugin_capability_check) do
      fun when is_function(fun, 2) -> fun.(user, capability) == true
      _ -> not is_nil(user) and Permissions.allows?(user, to_string(capability))
    end
  end

  @doc "The URL of a plugin page."
  def page_url(slug, route) do
    "#{Escalated.config(:route_prefix, "/support")}/admin/plugins/#{slug}/#{route}"
  end

  @doc """
  The shared `escalated.plugins` prop for `user`: `menuItems` from the active
  plugins' pages that declare a `menu` (admin items for admins only; items
  whose capability the user lacks left out), with empty `pageComponents` and
  `dashboardWidgets`. `%{}` with no active plugin.
  """
  def ui_extensions(user) do
    with [_ | _] <- registered_modules(),
         [_ | _] = active <- active_plugins() do
      admin? = Permissions.admin?(user)

      items =
        for module <- active,
            page <- pages(module),
            menu = page.menu,
            menu != nil,
            menu.section != "admin" or admin?,
            capable?(user, page.capability) do
          slug = module.slug()

          %{
            label: menu.label || page.title || page.component,
            route: page_url(slug, page.route),
            icon: menu.icon,
            position: menu.position,
            section: menu.section,
            plugin: slug
          }
        end

      %{
        menuItems: Enum.sort_by(items, & &1.position),
        pageComponents: %{},
        dashboardWidgets: []
      }
    else
      _ -> %{}
    end
  end

  defp normalize_page(module, page) when is_map(page) do
    route = page |> field(:route, field(page, :slug)) |> to_text() |> String.trim("/")
    component = page |> field(:component) |> to_text()

    if route == "" or component == "" do
      Logger.warning(
        "Escalated plugin #{module.slug()} declares a page without a route or component; skipped."
      )

      []
    else
      props = field(page, :props, %{})

      [
        %{
          route: route,
          component: component,
          title: field(page, :title),
          layout: to_text(field(page, :layout, "admin")),
          capability: field(page, :capability),
          props: if(is_map(props), do: props, else: %{}),
          menu: normalize_menu(field(page, :menu))
        }
      ]
    end
  end

  defp normalize_page(module, _page) do
    Logger.warning(
      "Escalated plugin #{module.slug()} declares a page that is not a map; skipped."
    )

    []
  end

  defp normalize_menu(menu) when is_map(menu) do
    %{
      label: field(menu, :label),
      icon: field(menu, :icon),
      position: field(menu, :position, 100),
      section: to_text(field(menu, :section, "admin"))
    }
  end

  defp normalize_menu(_menu), do: nil

  defp field(map, key, default \\ nil) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key))) do
      nil -> default
      value -> value
    end
  end

  defp to_text(nil), do: ""
  defp to_text(value), do: to_string(value)

  # Invoke an optional lifecycle callback on the plugin module for `slug`,
  # swallowing (but logging) any error so a misbehaving plugin cannot abort the
  # host's own state transition.
  defp run_lifecycle(slug, callback) do
    module = module_for_slug(slug)

    if module && function_exported?(module, callback, 0) do
      apply(module, callback, [])
    end

    :ok
  rescue
    error ->
      Logger.error("Escalated plugin #{slug} #{callback} raised: #{Exception.message(error)}")
      :ok
  end

  defp module_for_slug(slug) do
    Enum.find(registered_modules(), &(&1.slug() == slug))
  end

  defp optional(module, fun, args, default) do
    if function_exported?(module, fun, length(args)) do
      apply(module, fun, args)
    else
      default
    end
  end

  defp humanize(slug) do
    slug
    |> String.replace(["-", "_"], " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
