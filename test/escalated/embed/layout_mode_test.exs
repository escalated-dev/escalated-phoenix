defmodule Escalated.Embed.LayoutModeTest do
  @moduledoc """
  The admin embedded in the host's admin panel, layout mode (ADR
  2026-11-05-embeddable-admin): `config :escalated, :ui, embed: [enabled:
  true, prefix: "/admin/support", middleware: [:host_admin], layout:
  "Layouts/AdminLayout"]`. Every request goes through a host router compiled
  with that configuration (Escalated.Test.EmbedHost).
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Plugs
  alias Escalated.Schemas.{Permission, Role, RolePermission}
  alias Escalated.Test.EmbedHost

  @router Escalated.Test.EmbedLayoutRouter
  @fixture Path.expand("../../fixtures/embed/default-routes.json", __DIR__)
  @host "www.example.com"

  defmodule MenuPlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "acme-billing"

    @impl true
    def pages do
      [
        %{
          route: "settings",
          component: "AcmeBillingSettings",
          menu: %{label: "Billing", icon: "credit-card", position: 55}
        },
        %{route: "desk", component: "AcmeDesk", menu: %{label: "Desk", section: "agent"}}
      ]
    end
  end

  setup_all do
    EmbedHost.router!(@router, EmbedHost.base())
    :ok
  end

  setup do
    EmbedHost.put_embed()
    previous_plugins = Application.get_env(:escalated, :plugins)

    on_exit(fn ->
      EmbedHost.clear_embed()
      Application.delete_env(:escalated, :access)

      if previous_plugins,
        do: Application.put_env(:escalated, :plugins, previous_plugins),
        else: Application.delete_env(:escalated, :plugins)
    end)

    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    agent = host_user!(%{name: "Al Agent", is_agent: true})
    %{admin: admin, agent: agent}
  end

  defp host_visit(method, path, user, opts \\ []),
    do: EmbedHost.visit(@router, method, path, user, opts)

  defp props(conn, component), do: page!(conn, component)

  defp embedded_admin?(path),
    do:
      String.starts_with?(path, "/support/admin/") and
        not String.starts_with?(path, "/support/admin/settings/two-factor")

  describe "routes" do
    test "every admin route moves under the host prefix with the host middleware; nothing else moves" do
      expected =
        @fixture
        |> File.read!()
        |> Jason.decode!()
        |> Map.fetch!("routes")
        |> Enum.map(fn route ->
          if embedded_admin?(route["path"]) do
            # The standalone admin's pipelines, with the embed context
            # first and the host's middleware after the error page.
            [
              ":browser",
              "Escalated.Plugs.InertiaErrorPage",
              "Escalated.Plugs.ResolveTenant",
              "Escalated.Plugs.TicketVisibility",
              "Escalated.Plugs.EnsureAdmin",
              "Escalated.Plugs.RequireTwoFactor",
              "Escalated.Plugs.EnforceRoutePermissions" | rest
            ] = route["pipe_through"]

            %{
              route
              | "path" =>
                  String.replace_prefix(route["path"], "/support/admin", "/admin/support"),
                "pipe_through" =>
                  [
                    ":browser",
                    "Escalated.Plugs.ApplyEmbedContext",
                    "Escalated.Plugs.InertiaErrorPage",
                    ":host_admin",
                    "Escalated.Plugs.ResolveTenant",
                    "Escalated.Plugs.TicketVisibility",
                    "Escalated.Plugs.EnsureAdmin",
                    "Escalated.Plugs.RequireTwoFactor",
                    "Escalated.Plugs.EnforceRoutePermissions"
                  ] ++ rest
            }
          else
            route
          end
        end)

      current =
        Enum.map(@router.__route_table__(), fn route ->
          %{
            "verb" => route.verb |> to_string() |> String.upcase(),
            "path" => route.path,
            "controller" => inspect(route.plug),
            "action" => inspect(route.plug_opts),
            "helper" => route.helper,
            "pipe_through" => Enum.map(route.pipe_through, &inspect/1)
          }
        end)

      assert Enum.any?(expected, &String.starts_with?(&1["path"], "/admin/support/"))
      assert length(current) == length(expected)
      assert current -- expected == []
      assert expected -- current == []
    end

    test "the standalone admin URLs are not routed; agent, two-factor and the rest stay" do
      assert Phoenix.Router.route_info(@router, "GET", "/support/admin/tags", @host) == :error
      assert Phoenix.Router.route_info(@router, "GET", "/support/admin/settings", @host) == :error

      assert %{plug: Escalated.Controllers.Admin.TagController} =
               Phoenix.Router.route_info(@router, "GET", "/admin/support/tags", @host)

      assert %{plug: Escalated.Controllers.Agent.TicketController} =
               Phoenix.Router.route_info(@router, "GET", "/support/agent/tickets", @host)

      assert %{plug: Escalated.Controllers.Admin.TwoFactorController} =
               Phoenix.Router.route_info(
                 @router,
                 "GET",
                 "/support/admin/settings/two-factor",
                 @host
               )
    end

    test "an embedded page answers under the host prefix, through the host middleware", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.admin)
      props(conn, "Escalated/Admin/Tags/Index")
      assert get_resp_header(conn, "x-host-admin") == ["1"]
    end

    test "the host middleware can refuse", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.admin, headers: [{"x-host-deny", "1"}])
      assert conn.status == 403
      assert get_resp_header(conn, "x-host-admin") == ["1"]
      refute conn.resp_body =~ "Escalated/Admin/Tags/Index"
    end

    test "the old URL answers no route", ctx do
      assert_raise Phoenix.Router.NoRouteError, fn ->
        host_visit(:get, "/support/admin/tags", ctx.admin)
      end
    end

    test "Escalated's admin gate still refuses a non-admin", ctx do
      conn = host_visit(:get, "/admin/support/tags", ctx.agent)
      assert conn.status == 403
    end

    test "route permissions still apply while roles & permissions is on", ctx do
      {:ok, _} = Escalated.Tenancy.Provisioner.seed()
      Application.put_env(:escalated, :access, roles_permissions: true)

      conn = host_visit(:get, "/admin/support/tags", ctx.admin)
      assert conn.status == 403
    end

    test "redirects and the frontend's route table follow the move", ctx do
      conn =
        host_visit(:post, "/admin/support/tags", ctx.admin,
          body: %{tag: %{name: "Billing", slug: "billing"}}
        )

      assert conn.status in [302, 303]
      assert location(conn) == "/admin/support/tags"

      ziggy =
        host_visit(:get, "/admin/support/tags", ctx.admin) |> props("Escalated/Admin/Tags/Index")

      routes = ziggy["ziggy"]["routes"]

      assert routes["escalated.admin.tags.index"]["uri"] == "admin/support/tags"
      assert routes["escalated.admin.tickets.show"]["uri"] == "admin/support/tickets/{ticket}"

      assert routes["escalated.admin.two-factor.index"]["uri"] ==
               "support/admin/settings/two-factor"

      assert routes["escalated.agent.tickets.index"]["uri"] == "support/agent/tickets"
      assert routes["escalated.admin.chat.end"]["uri"] == "support/agent/chat/{session}/end"
      assert routes["escalated.customer.tickets.index"]["uri"] == "support/tickets"
    end

    test "every moved name resolves to a route the embedded router serves" do
      problems =
        for {name, route} <- Escalated.Routes.routes(),
            String.starts_with?(route.uri, "admin/support/"),
            method <- route.methods,
            method != "HEAD",
            path = "/" <> String.replace(route.uri, ~r/\{\w+\}/, "1"),
            Phoenix.Router.route_info(@router, method, path, @host) == :error,
            do: "#{name} #{method} #{path}"

      assert problems == []
    end
  end

  describe "the escalated.embed prop" do
    test "on an embedded response", ctx do
      props =
        host_visit(:get, "/admin/support/tags", ctx.admin) |> props("Escalated/Admin/Tags/Index")

      assert props["escalated"]["embed"] == %{
               "enabled" => true,
               "mode" => "layout",
               "layout" => "Layouts/AdminLayout",
               "route" => "escalated.admin.tags.index",
               "base_url" => "/admin/support",
               "allowed_origins" => []
             }
    end

    test "names the route of a page with parameters", ctx do
      props =
        host_visit(:get, "/admin/support/reports/agents", ctx.admin)
        |> props("Escalated/Admin/Reports/AgentMetrics")

      assert props["escalated"]["embed"]["route"] == "escalated.admin.reports.agents"
    end

    test "on every other page: shared, but not enabled", ctx do
      props =
        host_visit(:get, "/support/agent/tickets", ctx.admin)
        |> props("Escalated/Agent/TicketIndex")

      assert props["escalated"]["embed"]["enabled"] == false
      assert props["escalated"]["embed"]["route"] == nil
      assert props["escalated"]["embed"]["base_url"] == "/admin/support"
      assert is_list(props["escalated"]["navigation"])
    end

    test "layout mode adds no framing header", ctx do
      embedded = host_visit(:get, "/admin/support/tags", ctx.admin)
      standalone = host_visit(:get, "/support/agent/tickets", ctx.admin)

      for conn <- [embedded, standalone] do
        refute Enum.any?(
                 get_resp_header(conn, "content-security-policy"),
                 &(&1 =~ "frame-ancestors 'self'" and not (&1 =~ "base-uri"))
               )
      end

      assert get_resp_header(embedded, "x-frame-options") == ["DENY"]
      assert get_resp_header(standalone, "x-frame-options") == ["SAMEORIGIN"]
    end
  end

  describe "the escalated.navigation prop" do
    test "lists the admin menu in the standalone sidebar's order, marking the current page",
         ctx do
      props =
        host_visit(:get, "/admin/support/tags", ctx.admin) |> props("Escalated/Admin/Tags/Index")

      items = props["escalated"]["navigation"]

      assert Enum.map(items, & &1["key"]) == [
               "reports",
               "tickets",
               "departments",
               "sla-policies",
               "knowledge-base",
               "escalation-rules",
               "workflows",
               "automations",
               "webhooks",
               "tags",
               "custom-fields",
               "statuses",
               "canned-responses",
               "macros",
               "skills",
               "users",
               "capacity",
               "business-hours",
               "audit-log",
               "api-tokens",
               "custom-objects",
               "plugins",
               "import",
               "settings"
             ]

      tags = Enum.find(items, &(&1["key"] == "tags"))

      assert tags == %{
               "key" => "tags",
               "label" => "Tags",
               "route" => "escalated.admin.tags.index",
               "url" => "/admin/support/tags",
               "icon" => "tags",
               "position" => 60,
               "active" => true,
               "badge" => nil,
               "plugin" => nil,
               "children" => []
             }

      assert Enum.count(items, & &1["active"]) == 1
      assert Enum.find(items, &(&1["key"] == "automations"))["position"] == 53.5
      assert Enum.find(items, &(&1["key"] == "api-tokens"))["url"] == "/admin/support/api-tokens"
    end

    test "marks a parent item active on the pages below it", ctx do
      items =
        host_visit(:get, "/admin/support/reports/agents", ctx.admin)
        |> props("Escalated/Admin/Reports/AgentMetrics")
        |> get_in(["escalated", "navigation"])

      assert Enum.filter(items, & &1["active"]) |> Enum.map(& &1["key"]) == ["reports"]
    end

    test "is empty for a user who fails the admin gate", ctx do
      props =
        host_visit(:get, "/support/agent/tickets", ctx.agent)
        |> props("Escalated/Agent/TicketIndex")

      assert props["escalated"]["navigation"] == []
    end

    test "Roles only while roles & permissions is on, and items the user's roles do not grant are left out",
         ctx do
      {:ok, _} = Escalated.Tenancy.Provisioner.seed()

      off = Escalated.admin_navigation(ctx.admin, nil) |> Enum.map(& &1.key)
      refute "roles" in off
      assert "settings" in off

      Application.put_env(:escalated, :access, roles_permissions: true)

      role = Escalated.repo().insert!(Role.changeset(%Role{}, %{name: "nav", slug: "nav-role"}))

      for permission <-
            Escalated.repo().all(
              from(p in Permission, where: p.slug in ["ticket.view", "role.view", "tag.view"])
            ) do
        Escalated.repo().insert!(%RolePermission{role_id: role.id, permission_id: permission.id})
      end

      {:ok, _} = Escalated.Roles.assign(ctx.admin.id, "nav-role")

      keys = Escalated.admin_navigation(ctx.admin, nil) |> Enum.map(& &1.key)
      assert "tickets" in keys
      assert "roles" in keys
      assert "tags" in keys
      refute "settings" in keys
      refute "departments" in keys
    end

    test "includes active plugins' admin menu items, sorted with the core items", ctx do
      Application.put_env(:escalated, :plugins, [MenuPlugin])
      {:ok, _} = Escalated.Plugins.activate("acme-billing")

      items =
        host_visit(:get, "/admin/support/plugins/acme-billing/settings", ctx.admin)
        |> props("Escalated/Plugin/Page")
        |> get_in(["escalated", "navigation"])

      keys = Enum.map(items, & &1["key"])
      plugin = Enum.find(items, &(&1["plugin"] == "acme-billing"))

      assert plugin == %{
               "key" => "plugin:acme-billing:0",
               "label" => "Billing",
               "route" => nil,
               "url" => "/admin/support/plugins/acme-billing/settings",
               "icon" => "credit-card",
               "position" => 55,
               "active" => true,
               "badge" => nil,
               "plugin" => "acme-billing",
               "children" => []
             }

      assert Enum.slice(keys, 8..10) == ["webhooks", "plugin:acme-billing:0", "tags"]
      refute Enum.any?(items, &(&1["label"] == "Desk"))
    end
  end

  test "the embedded routes run the embed context plug and the host pipeline" do
    route = Phoenix.Router.route_info(@router, "GET", "/admin/support/tags", @host)
    assert route.plug == Escalated.Controllers.Admin.TagController

    pipes =
      @router.__route_table__()
      |> Enum.find(&(&1.path == "/admin/support/tags" and &1.verb == :get))
      |> Map.fetch!(:pipe_through)

    assert Plugs.ApplyEmbedContext in pipes
    assert :host_admin in pipes
  end
end
