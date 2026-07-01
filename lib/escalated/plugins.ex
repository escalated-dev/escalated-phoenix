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
    List.wrap(Escalated.config(:plugins, []))
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
