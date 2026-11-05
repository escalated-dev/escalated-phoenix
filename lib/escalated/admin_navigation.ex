defmodule Escalated.AdminNavigation do
  @moduledoc """
  Escalated's admin menu as data, so a host can list it in its own sidebar
  (ADR 2026-11-05-embeddable-admin). Shared as `escalated.navigation` while
  the admin is embedded, and returned by `Escalated.admin_navigation/2` for
  server-rendered (HEEx) layouts whether or not it is.

  Filtered server-side so a host sidebar never links to a screen that would
  answer 403 or 404: the admin gate (unless the host replaced it), screens
  whose feature is off, and, while roles & permissions is on, each screen's
  permission (`Escalated.RoutePermissions`). Active plugins' admin menu items
  are merged in.
  """

  alias Escalated.Controllers.Admin
  alias Escalated.{Embed, Permissions, RoutePermissions}

  # {key (also the icon key), label, frontend route name, position, path
  # below the admin, {controller, action}}. Labels and positions match the
  # standalone admin sidebar in the shared frontend.
  @items [
    {"reports", "Reports", "escalated.admin.reports", 10, "/reports",
     {Admin.ReportController, :index}},
    {"tickets", "Tickets", "escalated.admin.tickets.index", 20, "/tickets",
     {Admin.TicketController, :index}},
    {"departments", "Departments", "escalated.admin.departments.index", 30, "/departments",
     {Admin.DepartmentController, :index}},
    {"sla-policies", "SLA Policies", "escalated.admin.sla-policies.index", 40, "/sla-policies",
     {Admin.SlaPolicyController, :index}},
    {"knowledge-base", "Knowledge Base", "escalated.admin.kb-articles.index", 45, "/kb-articles",
     {Admin.ArticleController, :index}},
    {"escalation-rules", "Escalation Rules", "escalated.admin.escalation-rules.index", 50,
     "/escalation-rules", {Admin.EscalationRuleController, :index}},
    {"workflows", "Workflows", "escalated.admin.workflows.index", 53, "/workflows",
     {Admin.WorkflowController, :index}},
    {"automations", "Automations", "escalated.admin.automations.index", 53.5, "/automations",
     {Admin.AutomationController, :index}},
    {"webhooks", "Webhooks", "escalated.admin.webhooks.index", 54, "/webhooks",
     {Admin.WebhookController, :index}},
    {"tags", "Tags", "escalated.admin.tags.index", 60, "/tags", {Admin.TagController, :index}},
    {"custom-fields", "Custom Fields", "escalated.admin.custom-fields.index", 62,
     "/custom-fields", {Admin.CustomFieldController, :index}},
    {"statuses", "Statuses", "escalated.admin.statuses.index", 64, "/statuses",
     {Admin.StatusController, :index}},
    {"canned-responses", "Canned Responses", "escalated.admin.canned-responses.index", 70,
     "/canned-responses", {Admin.CannedResponseController, :index}},
    {"macros", "Macros", "escalated.admin.macros.index", 80, "/macros",
     {Admin.MacroController, :index}},
    {"newsletters", "Newsletters", "escalated.admin.newsletters.index", 81, :newsletters,
     {Admin.NewsletterController, :index}},
    {"skills", "Skills", "escalated.admin.skills.index", 82, "/skills",
     {Admin.SkillController, :index}},
    {"users", "Users", "escalated.admin.users.index", 83, "/users",
     {Admin.UserController, :index}},
    {"roles", "Roles", "escalated.admin.roles.index", 84, "/roles",
     {Admin.RoleController, :index}},
    {"capacity", "Capacity", "escalated.admin.capacity.index", 85, "/capacity",
     {Admin.CapacityController, :index}},
    {"business-hours", "Business Hours", "escalated.admin.business-hours.index", 86,
     "/business-hours", {Admin.BusinessHoursController, :index}},
    {"audit-log", "Audit Log", "escalated.admin.audit-log", 88, "/audit-log",
     {Admin.AuditLogController, :index}},
    {"api-tokens", "API Tokens", "escalated.admin.api-tokens.index", 90, "/api-tokens",
     {Admin.ApiTokenController, :index}},
    {"custom-objects", "Custom Objects", "escalated.admin.custom-objects.index", 92,
     "/custom-objects", {Admin.CustomObjectController, :index}},
    {"plugins", "Plugins", "escalated.admin.plugins.index", 95, "/plugins",
     {Admin.PluginController, :index}},
    {"import", "Import", "escalated.admin.import.index", 97, "/import",
     {Admin.ImportController, :index}},
    {"settings", "Settings", "escalated.admin.settings", 100, "/settings",
     {Admin.SettingsController, :index}}
  ]

  @doc "The core items' keys, in the standalone sidebar's order."
  def keys, do: Enum.map(@items, &elem(&1, 0))

  @doc """
  The admin menu for `user` on the request `conn` (nil: no item is active):
  a list of `%{key, label, route, url, icon, position, active, badge, plugin,
  children}`, sorted by `position`.
  """
  @spec for(term(), Plug.Conn.t() | nil) :: [map()]
  def for(nil, _conn), do: []

  def for(user, conn) do
    if Embed.replaces_admin_gate?() or Permissions.admin?(user),
      do: build(user, conn),
      else: []
  end

  defp build(user, conn) do
    path = request_path(conn)
    names = Escalated.Routes.routes()

    granted =
      if Escalated.AccessFeatures.roles_permissions?(),
        do: Permissions.list_slugs_for_user(user),
        else: nil

    core =
      for {key, label, name, position, below, {controller, action}} <- @items,
          url = url(below),
          url != nil,
          key != "roles" or Escalated.AccessFeatures.roles_permissions?(),
          permitted?(granted, controller, action) do
        route = if Map.has_key?(names, name), do: name, else: nil
        item(key, label, route, url, key, position, path)
      end

    plugins =
      user
      |> plugin_items()
      |> Enum.with_index()
      |> Enum.map(fn {menu, index} ->
        slug = to_string(menu[:plugin])

        "plugin:#{slug}:#{index}"
        |> item(to_string(menu[:label]), nil, menu[:route], menu[:icon], menu[:position], path)
        |> Map.merge(%{badge: menu[:badge], plugin: menu[:plugin]})
      end)

    (core ++ plugins)
    |> Enum.with_index()
    |> Enum.sort_by(fn {item, index} -> {item.position, index} end)
    |> Enum.map(&elem(&1, 0))
  end

  defp url(:newsletters) do
    if newsletters_enabled?(),
      do: Escalated.config(:route_prefix, "/support") <> "/admin/newsletters",
      else: nil
  end

  defp url(below), do: Embed.admin_path(below)

  # The newsletter routes are compiled in only with `enable_newsletters`.
  defp newsletters_enabled? do
    Application.get_env(:escalated, :enable_newsletters, false) in [true, "true", 1, "1"] and
      Code.ensure_loaded?(Admin.NewsletterController)
  end

  defp permitted?(nil, _controller, _action), do: true

  defp permitted?(granted, controller, action) do
    case RoutePermissions.required(controller, action) do
      nil -> false
      required -> required -- granted == []
    end
  end

  defp item(key, label, route, url, icon, position, path) do
    %{
      key: key,
      label: label,
      route: route,
      url: url,
      icon: icon,
      position: position,
      active: active?(path, url),
      badge: nil,
      plugin: nil,
      children: []
    }
  end

  defp active?(nil, _url), do: false

  defp active?(path, url) do
    target = url |> URI.parse() |> Map.get(:path) |> Kernel.||(url) |> String.trim_trailing("/")
    path == target or String.starts_with?(path, target <> "/")
  end

  defp request_path(%Plug.Conn{request_path: path}), do: "/" <> String.trim_leading(path, "/")
  defp request_path(_), do: nil

  # Admin-section menu items of active plugins, already filtered by the plugin
  # contract (admin items for admins, each page's capability).
  defp plugin_items(user) do
    case Escalated.Plugins.ui_extensions(user) do
      %{menuItems: items} -> Enum.filter(items, &(&1[:section] in [nil, "admin"]))
      _ -> []
    end
  rescue
    _ -> []
  end
end
