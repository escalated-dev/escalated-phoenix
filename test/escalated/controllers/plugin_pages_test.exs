defmodule Escalated.Controllers.PluginPagesTest do
  @moduledoc """
  Plugin pages (escalated-developer-context `domain-model/plugin-contract.md`,
  "Pages: `Escalated/Plugin/Page`" and "UI extensions"): a plugin declares
  pages with the optional `pages/0` callback; each page of an **active**
  plugin is served at `{prefix}/admin/plugins/{slug}/{route}` as the shared
  `Escalated/Plugin/Page`, and pages with a `menu` show up in the shared
  `escalated.plugins.menuItems`. Every request goes through the router.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Plugins
  alias Escalated.Schemas.{Permission, Role, RolePermission}
  alias Escalated.Test.SharedPropsRouter

  @component "Escalated/Plugin/Page"

  defmodule PagesPlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "acme-billing"

    @impl true
    def name, do: "Acme Billing"

    @impl true
    def pages do
      [
        %{
          route: "/settings",
          component: "AcmeBillingSettings",
          title: "Billing settings",
          menu: %{label: "Billing", icon: "credit-card", position: 40}
        },
        %{
          route: "reports/daily",
          component: "AcmeDailyReport",
          title: "Daily report",
          layout: "agent",
          props: %{"static" => true}
        },
        %{route: "secret", component: "AcmeSecret", capability: "settings.manage"},
        %{
          route: "agents",
          component: "AcmeAgentPage",
          menu: %{label: "Billing desk", section: "agent"}
        },
        %{
          route: "locked-menu",
          component: "AcmeLocked",
          capability: "settings.manage",
          menu: %{label: "Locked"}
        },
        %{route: "broken", component: "AcmeBroken"},
        %{route: "", component: "NoRoute"},
        %{route: "no-component", component: ""}
      ]
    end

    @impl true
    def page_props("AcmeBillingSettings", user), do: %{"viewer_id" => user.id, "plan" => "pro"}
    def page_props("AcmeBroken", _user), do: raise("boom")
    def page_props(_component, _user), do: nil
  end

  defmodule PagelessPlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "pageless"
  end

  defmodule InactivePlugin do
    @moduledoc false
    @behaviour Escalated.Plugins.Plugin

    @impl true
    def slug, do: "inactive-plugin"

    @impl true
    def pages,
      do: [%{route: "home", component: "InactiveHome", menu: %{label: "Inactive"}}]
  end

  setup do
    saved = %{
      plugins: Application.get_env(:escalated, :plugins),
      plugin_capability_check: Application.get_env(:escalated, :plugin_capability_check)
    }

    on_exit(fn ->
      Application.delete_env(:escalated, :access)

      Enum.each(saved, fn
        {key, nil} -> Application.delete_env(:escalated, key)
        {key, value} -> Application.put_env(:escalated, key, value)
      end)
    end)

    Application.put_env(:escalated, :plugins, [PagesPlugin, PagelessPlugin, InactivePlugin])
    {:ok, _} = Plugins.activate("acme-billing")
    {:ok, _} = Plugins.activate("pageless")

    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})
    agent = host_user!(%{name: "Al Agent", is_agent: true})

    %{admin: admin, agent: agent}
  end

  defp shared_plugins(path, user) do
    conn(:get, path)
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> SharedPropsRouter.call(SharedPropsRouter.init([]))
    |> then(fn conn ->
      assert conn.status == 200, "#{path} answered #{conn.status}: #{conn.resp_body}"
      Jason.decode!(conn.resp_body)["props"]["escalated"]["plugins"]
    end)
  end

  describe "an active plugin's page" do
    test "renders Escalated/Plugin/Page with the contract's props", ctx do
      props =
        visit(:get, "/support/admin/plugins/acme-billing/settings", ctx.admin)
        |> page!(@component)

      assert_keys(props, ~w(plugin component layout props))
      assert props["plugin"] == "acme-billing"
      assert props["component"] == "AcmeBillingSettings"
      assert props["layout"] == "admin"
      assert props["title"] == "Billing settings"
      assert props["props"] == %{"viewer_id" => ctx.admin.id, "plan" => "pro"}
    end

    test "serves a nested route with its own layout and static props", ctx do
      props =
        visit(:get, "/support/admin/plugins/acme-billing/reports/daily", ctx.admin)
        |> page!(@component)

      assert props["component"] == "AcmeDailyReport"
      assert props["layout"] == "agent"
      assert props["props"] == %{"static" => true}
    end

    test "sends {} as props when the plugin's page_props raises", ctx do
      props =
        visit(:get, "/support/admin/plugins/acme-billing/broken", ctx.admin)
        |> page!(@component)

      assert props["props"] == %{}
    end

    test "skips entries with an empty route or component", ctx do
      assert visit(:get, "/support/admin/plugins/acme-billing/no-component", ctx.admin).status ==
               404

      routes = PagesPlugin |> Plugins.pages() |> Enum.map(& &1.route)
      assert routes == ~w(settings reports/daily secret agents locked-menu broken)
    end
  end

  describe "refused" do
    test "an inactive plugin's page is a 404", ctx do
      assert visit(:get, "/support/admin/plugins/inactive-plugin/home", ctx.admin).status == 404

      {:ok, _} = Plugins.deactivate("acme-billing")
      assert visit(:get, "/support/admin/plugins/acme-billing/settings", ctx.admin).status == 404
    end

    test "an unknown plugin or an undeclared route is a 404", ctx do
      assert visit(:get, "/support/admin/plugins/nope/settings", ctx.admin).status == 404
      assert visit(:get, "/support/admin/plugins/acme-billing/nope", ctx.admin).status == 404
      assert visit(:get, "/support/admin/plugins/pageless/settings", ctx.admin).status == 404
    end

    test "agents and guests never get the page", ctx do
      assert visit(:get, "/support/admin/plugins/acme-billing/settings", ctx.agent).status == 403
      assert visit(:get, "/support/admin/plugins/acme-billing/settings", nil).status == 401
    end

    test "a page whose capability the host check refuses is a 403", ctx do
      Application.put_env(:escalated, :plugin_capability_check, fn user, capability ->
        capability == "settings.manage" and user.name == "Somebody else"
      end)

      conn = visit(:get, "/support/admin/plugins/acme-billing/secret", ctx.admin)
      assert conn.status == 403

      # Pages without a capability are not affected by the check.
      assert visit(:get, "/support/admin/plugins/acme-billing/settings", ctx.admin).status == 200

      Application.put_env(:escalated, :plugin_capability_check, fn _user, _cap -> true end)
      assert visit(:get, "/support/admin/plugins/acme-billing/secret", ctx.admin).status == 200
    end

    test "with roles & permissions on, the capability is a permission slug", ctx do
      {:ok, _} = Escalated.Tenancy.Provisioner.seed()
      Application.put_env(:escalated, :access, roles_permissions: true)

      without = role_with!(["ticket.view"])
      with_it = role_with!(["ticket.view", "settings.manage"])

      {:ok, _} = Escalated.Roles.assign(ctx.admin.id, without.slug)
      assert visit(:get, "/support/admin/plugins/acme-billing/secret", ctx.admin).status == 403
      assert visit(:get, "/support/admin/plugins/acme-billing/settings", ctx.admin).status == 200

      {:ok, _} = Escalated.Roles.assign(ctx.admin.id, with_it.slug)
      assert visit(:get, "/support/admin/plugins/acme-billing/secret", ctx.admin).status == 200
    end
  end

  describe "escalated.plugins" do
    test "carries menu items for active plugins' pages", ctx do
      plugins = shared_plugins("/support/admin/tickets", ctx.admin)

      assert_keys(plugins, ~w(menuItems pageComponents dashboardWidgets), "escalated.plugins")
      assert plugins["pageComponents"] == %{}
      assert plugins["dashboardWidgets"] == []

      assert Enum.sort_by(plugins["menuItems"], & &1["label"]) == [
               %{
                 "label" => "Billing",
                 "route" => "/support/admin/plugins/acme-billing/settings",
                 "icon" => "credit-card",
                 "position" => 40,
                 "section" => "admin",
                 "plugin" => "acme-billing"
               },
               %{
                 "label" => "Billing desk",
                 "route" => "/support/admin/plugins/acme-billing/agents",
                 "icon" => nil,
                 "position" => 100,
                 "section" => "agent",
                 "plugin" => "acme-billing"
               },
               %{
                 "label" => "Locked",
                 "route" => "/support/admin/plugins/acme-billing/locked-menu",
                 "icon" => nil,
                 "position" => 100,
                 "section" => "admin",
                 "plugin" => "acme-billing"
               }
             ]
    end

    test "leaves out items whose capability the viewer lacks", ctx do
      Application.put_env(:escalated, :plugin_capability_check, fn _user, _cap -> false end)

      labels =
        shared_plugins("/support/admin/tickets", ctx.admin)["menuItems"]
        |> Enum.map(& &1["label"])
        |> Enum.sort()

      assert labels == ["Billing", "Billing desk"]
    end

    test "admin menu items go to admins only", ctx do
      labels =
        shared_plugins("/support/agent/tickets", ctx.agent)["menuItems"]
        |> Enum.map(& &1["label"])

      assert labels == ["Billing desk"]
    end

    test "is {} with no active plugin", ctx do
      {:ok, _} = Plugins.deactivate("acme-billing")
      {:ok, _} = Plugins.deactivate("pageless")

      assert shared_plugins("/support/admin/tickets", ctx.admin) == %{}
    end
  end

  defp role_with!(slugs) do
    slug = "custom-#{System.unique_integer([:positive])}"
    repo = Escalated.repo()
    role = repo.insert!(Role.changeset(%Role{}, %{name: slug, slug: slug}))

    for permission <- repo.all(from(p in Permission, where: p.slug in ^slugs)) do
      repo.insert!(%RolePermission{role_id: role.id, permission_id: permission.id})
    end

    role
  end
end
