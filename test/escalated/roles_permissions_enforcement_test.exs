defmodule Escalated.RolesPermissionsEnforcementTest do
  @moduledoc """
  ADR 2026-10-29-configurable-access-features: roles & permissions is an
  install-level switch (`config :escalated, access: [roles_permissions: true]`
  or `ESCALATED_ROLES_PERMISSIONS`). Off, the host gates decide everything and
  the roles screens answer 404. On, every admin, agent and staff API route
  also needs its permission from the user's roles. Every request goes through
  the router, the way a browser or API client reaches it.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.{AccessFeatures, Permissions, RoutePermissions}
  alias Escalated.Schemas.{Permission, Role, RolePermission, Ticket}
  alias Escalated.Services.{ApiTokenService, SettingsService, TicketService}
  alias Escalated.Test.{Router, SharedPropsRouter}

  defp repo, do: Escalated.repo()

  setup do
    {:ok, _} = Escalated.Tenancy.Provisioner.seed()
    previous_env = System.get_env("ESCALATED_ROLES_PERMISSIONS")
    System.delete_env("ESCALATED_ROLES_PERMISSIONS")

    on_exit(fn ->
      Application.delete_env(:escalated, :access)
      Application.delete_env(:escalated, :api_tokens_enabled)

      if previous_env,
        do: System.put_env("ESCALATED_ROLES_PERMISSIONS", previous_env),
        else: System.delete_env("ESCALATED_ROLES_PERMISSIONS")
    end)

    customer = host_user!(%{name: "Cy Customer"})

    {:ok, ticket} =
      TicketService.create(%{
        subject: "Refund please",
        description: "Charged twice",
        requester_id: customer.id,
        requester_type: "user"
      })

    %{ticket: ticket, customer: customer}
  end

  defp staff!(kind, role \\ nil) do
    user = host_user!(%{name: "#{kind}", is_agent: true, is_admin: kind == :admin})
    if role, do: {:ok, _} = Escalated.Roles.assign(user.id, role)
    user
  end

  defp role_with!(slugs) do
    slug = "custom-#{System.unique_integer([:positive])}"
    role = repo().insert!(Role.changeset(%Role{}, %{name: slug, slug: slug}))

    for permission <- repo().all(from(p in Permission, where: p.slug in ^slugs)) do
      repo().insert!(%RolePermission{role_id: role.id, permission_id: permission.id})
    end

    role
  end

  defp give!(user, %Role{slug: slug}), do: {:ok, _} = Escalated.Roles.assign(user.id, slug)

  defp enforce!, do: Application.put_env(:escalated, :access, roles_permissions: true)

  defp redirected?(conn), do: conn.status in [302, 303]

  defp shared_props(path, user) do
    conn(:get, path)
    |> init_test_session(%{})
    |> assign(:current_user, user)
    |> put_req_header("x-inertia", "true")
    |> put_req_header("x-inertia-version", inertia_version())
    |> SharedPropsRouter.call(SharedPropsRouter.init([]))
    |> then(fn conn ->
      assert conn.status == 200, "#{path} answered #{conn.status}: #{conn.resp_body}"
      Jason.decode!(conn.resp_body)["props"]["escalated"]
    end)
  end

  defp api(method, path, plain, body \\ nil) do
    base =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    base
    |> init_test_session(%{})
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> plain)
    |> Router.call(Router.init([]))
  end

  # --- Switch off (the default) ----------------------------------------------

  test "every access switch is off by default" do
    refute AccessFeatures.roles_permissions?()
    assert AccessFeatures.shared() == %{roles_permissions: false, two_factor: false, sso: false}
  end

  test "the roles screens and role assignment answer 404 while the switch is off" do
    admin = staff!(:admin, "admin")
    other = staff!(:agent, "agent")

    assert visit(:get, "/support/admin/roles", admin).status == 404
    assert visit(:get, "/support/admin/roles/create", admin).status == 404
    assert visit(:post, "/support/admin/roles", admin, %{"name" => "X"}).status == 404

    assert visit(:put, "/support/admin/users/#{other.id}/roles", admin, %{"role_ids" => []}).status ==
             404

    refute repo().get_by(Role, slug: "x")
  end

  test "the gates alone decide while the switch is off", %{ticket: ticket} do
    agent = staff!(:agent, "light_agent")
    other = staff!(:agent)

    conn =
      visit(:post, "/support/agent/tickets/#{ticket.reference}/assign", agent, %{
        "agent_id" => other.id
      })

    assert redirected?(conn)
    assert repo().get!(Ticket, ticket.id).assigned_to == other.id

    assert visit(:get, "/support/admin/departments", staff!(:admin)).status == 200
  end

  test "shares the switches and a wildcard permission set for staff while off", ctx do
    props = shared_props("/support/admin/departments", staff!(:admin))

    assert props["features"]["roles_permissions"] == false
    assert props["features"]["two_factor"] == false
    assert props["features"]["sso"] == false
    assert props["permissions"] == ["*"]

    assert Permissions.shared_slugs(ctx.customer) == []
  end

  test "the switch is config or env only; a stored setting of the same name changes nothing" do
    admin = staff!(:admin, "admin")

    visit(:post, "/support/admin/settings", admin, %{"roles_permissions" => true})
    SettingsService.set("roles_permissions", "1", "general")

    refute AccessFeatures.roles_permissions?()
    assert visit(:get, "/support/admin/roles", admin).status == 404

    System.put_env("ESCALATED_ROLES_PERMISSIONS", "true")
    assert AccessFeatures.roles_permissions?()
    assert visit(:get, "/support/admin/roles", admin).status == 200

    # Config, when set, wins over the environment.
    Application.put_env(:escalated, :access, roles_permissions: false)
    refute AccessFeatures.roles_permissions?()
  end

  test "two-factor and SSO stay reported off until this package enforces them" do
    Application.put_env(:escalated, :access, two_factor: true, sso: true)

    refute AccessFeatures.two_factor?()
    refute AccessFeatures.sso?()

    props = shared_props("/support/admin/departments", staff!(:admin))
    assert props["features"]["two_factor"] == false
    assert props["features"]["sso"] == false
  end

  test "newsletter permissions apply only while the switch is on" do
    alias Escalated.Services.Newsletter.Permission, as: NewsletterPermission

    assert NewsletterPermission.allowed?(staff!(:admin), "newsletters.manage")

    enforce!()
    refute NewsletterPermission.allowed?(staff!(:admin), "newsletters.manage")
    assert NewsletterPermission.allowed?(staff!(:admin, "admin"), "newsletters.manage")
  end

  # --- Switch on ---------------------------------------------------------------

  test "the roles screens work for a user whose role grants them while on" do
    enforce!()
    admin = staff!(:admin, "admin")

    props = visit(:get, "/support/admin/roles", admin) |> page!("Escalated/Admin/Roles/Index")
    assert Enum.any?(props["roles"], &(&1["slug"] == "light_agent"))

    assert shared_props("/support/admin/roles", admin)["features"]["roles_permissions"] == true
  end

  test "passing the admin gate without a role grants nothing" do
    enforce!()
    admin = staff!(:admin)

    assert visit(:get, "/support/admin/departments", admin).status == 403
    assert visit(:get, "/support/admin/roles", admin).status == 403
    assert visit(:post, "/support/admin/settings", admin, %{}).status == 403
  end

  test "an admin with the admin role gets through" do
    enforce!()
    admin = staff!(:admin, "admin")

    assert visit(:get, "/support/admin/departments", admin).status == 200
    assert visit(:get, "/support/admin/settings", admin).status == 200
  end

  test "admin reads and writes need separate permissions" do
    enforce!()
    admin = staff!(:admin)
    give!(admin, role_with!(["department.view"]))

    assert visit(:get, "/support/admin/departments", admin).status == 200

    conn = visit(:post, "/support/admin/departments", admin, %{"name" => "Billing"})
    assert conn.status == 403
    assert conn.resp_body =~ "department.create"
    refute repo().get_by(Escalated.Schemas.Department, name: "Billing")

    assert visit(:get, "/support/admin/webhooks", admin).status == 403
  end

  test "shares the user's real permission slugs while on" do
    enforce!()
    admin = staff!(:admin)
    give!(admin, role_with!(["department.view"]))

    props = shared_props("/support/admin/departments", admin)
    assert props["features"]["roles_permissions"] == true
    assert props["permissions"] == ["department.view"]
  end

  test "a light agent can view a ticket and add a note, and nothing more", %{ticket: ticket} do
    enforce!()
    agent = staff!(:agent, "light_agent")
    other = staff!(:agent)
    ref = ticket.reference

    assert visit(:get, "/support/agent/tickets/#{ref}", agent).status == 200

    assert redirected?(
             visit(:post, "/support/agent/tickets/#{ref}/note", agent, %{"body" => "Internal"})
           )

    assert visit(:post, "/support/agent/tickets/#{ref}/assign", agent, %{"agent_id" => other.id}).status ==
             403

    assert visit(:post, "/support/agent/tickets/#{ref}/priority", agent, %{"priority" => "urgent"}).status ==
             403

    assert visit(:post, "/support/agent/tickets/#{ref}/status", agent, %{"status" => "closed"}).status ==
             403

    assert visit(:post, "/support/admin/tickets/bulk", staff!(:admin, "light_agent"), %{
             "ticket_ids" => [ticket.id],
             "action" => "delete"
           }).status == 403

    fresh = repo().get!(Ticket, ticket.id)
    assert fresh.assigned_to == nil
    assert to_string(fresh.priority) == to_string(ticket.priority)
    assert to_string(fresh.status) == to_string(ticket.status)
  end

  test "a full agent can assign", %{ticket: ticket} do
    enforce!()
    agent = staff!(:agent, "agent")
    other = staff!(:agent)

    assert redirected?(
             visit(:post, "/support/agent/tickets/#{ticket.reference}/assign", agent, %{
               "agent_id" => other.id
             })
           )

    assert repo().get!(Ticket, ticket.id).assigned_to == other.id
  end

  test "closing, resolving or reopening needs ticket.close", %{ticket: ticket} do
    enforce!()
    agent = staff!(:agent)
    give!(agent, role_with!(["ticket.view", "ticket.edit"]))
    path = "/support/agent/tickets/#{ticket.reference}/status"

    for status <- ~w(closed resolved reopened) do
      assert visit(:post, path, agent, %{"status" => status}).status == 403
    end

    assert redirected?(visit(:post, path, agent, %{"status" => "in_progress"}))
    assert to_string(repo().get!(Ticket, ticket.id).status) == "in_progress"

    give!(agent, role_with!(["ticket.close"]))
    assert redirected?(visit(:post, path, agent, %{"status" => "resolved"}))
    assert to_string(repo().get!(Ticket, ticket.id).status) == "resolved"
  end

  test "each bulk action is checked against its own permission", %{ticket: ticket} do
    enforce!()
    agent = staff!(:agent, "light_agent")
    other = staff!(:agent)

    bulk = fn user, action, value ->
      visit(:post, "/support/agent/tickets/bulk", user, %{
        "ticket_ids" => [ticket.id],
        "action" => action,
        "value" => value
      })
    end

    assert bulk.(agent, "assign", other.id).status == 403
    assert bulk.(agent, "delete", nil).status == 403
    assert bulk.(agent, "priority", "urgent").status == 403

    editor = staff!(:agent)
    give!(editor, role_with!(["ticket.view", "ticket.edit"]))
    assert bulk.(editor, "status", "closed").status == 403
    assert bulk.(editor, "assign", other.id).status == 403
    assert redirected?(bulk.(editor, "priority", "urgent"))

    fresh = repo().get!(Ticket, ticket.id)
    assert fresh.assigned_to == nil
    assert to_string(fresh.priority) == "urgent"
  end

  test "the staff API checks the token owner's permissions", %{ticket: ticket} do
    enforce!()
    Application.put_env(:escalated, :api_tokens_enabled, true)
    agent = staff!(:agent, "light_agent")
    other = staff!(:agent)
    {:ok, %{plain_text_token: plain}} = ApiTokenService.create(agent.id, "CI", ["agent"], nil)

    assert api(:get, "/support/api/v1/tickets/#{ticket.reference}", plain).status == 200

    assert api(:post, "/support/api/v1/tickets/#{ticket.reference}/assign", plain, %{
             "agent_id" => other.id
           }).status == 403

    assert repo().get!(Ticket, ticket.id).assigned_to == nil
  end

  test "every admin, agent and staff API route is in the route-permission map" do
    unmapped =
      Router.__routes__()
      |> Enum.filter(fn route ->
        String.starts_with?(route.path, ["/support/admin/", "/support/agent/"]) or
          route.plug == Escalated.Controllers.Api.TicketController
      end)
      |> Enum.reject(&RoutePermissions.mapped?(&1.plug, &1.plug_opts))
      |> Enum.map(&"#{&1.verb} #{&1.path} (#{inspect(&1.plug)}.#{&1.plug_opts})")

    assert unmapped == []
  end

  defmodule UnmappedController do
    use Phoenix.Controller, formats: [:json]
    def show(conn, _params), do: json(conn, %{ok: true})
  end

  defmodule UnmappedRouter do
    use Phoenix.Router

    scope "/" do
      pipe_through Escalated.Plugs.EnforceRoutePermissions
      get "/unmapped", UnmappedController, :show
    end
  end

  test "a staff route missing from the map is refused" do
    enforce!()

    conn =
      conn(:get, "/unmapped")
      |> assign(:current_user, staff!(:admin, "admin"))
      |> UnmappedRouter.call(UnmappedRouter.init([]))

    assert conn.status == 403
    assert conn.resp_body =~ "no permission mapping"
  end

  test "mix escalated.roles.assign gives a user a role" do
    user = staff!(:admin)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    Mix.Tasks.Escalated.Roles.Assign.run([user.email, "admin"])
    assert "role.manage" in Permissions.list_slugs_for_user(user)

    assert_raise Mix.Error, ~r/No user/, fn ->
      Mix.Tasks.Escalated.Roles.Assign.run(["nobody@example.test", "admin"])
    end

    assert_raise Mix.Error, ~r/No role/, fn ->
      Mix.Tasks.Escalated.Roles.Assign.run([user.email, "nope"])
    end
  end

  test "a role manager sets a user's roles while on" do
    enforce!()
    admin = staff!(:admin, "admin")
    agent = staff!(:agent, "agent")
    light = repo().get_by!(Role, slug: "light_agent")

    conn =
      visit(:put, "/support/admin/users/#{agent.id}/roles", admin, %{"role_ids" => [light.id]})

    assert redirected?(conn)

    slugs = Permissions.list_slugs_for_user(agent)
    refute "ticket.assign" in slugs
    assert "reply.create_internal" in slugs

    props = visit(:get, "/support/admin/users", admin) |> page!("Escalated/Admin/Users/Index")
    assert Enum.any?(props["roles"], &(&1["slug"] == "light_agent"))
    assert Enum.find(props["users"]["data"], &(&1["id"] == agent.id))["roles"] == ["light_agent"]
  end

  test "role changes need role.manage" do
    enforce!()
    agent = staff!(:agent, "agent")
    light = repo().get_by!(Role, slug: "light_agent")
    admin = staff!(:admin)
    give!(admin, role_with!(["user.view", "user.manage"]))

    assert visit(:put, "/support/admin/users/#{agent.id}/roles", admin, %{
             "role_ids" => [light.id]
           }).status == 403

    assert "ticket.assign" in Permissions.list_slugs_for_user(agent)
  end

  test "a role manager cannot remove their own role management" do
    enforce!()
    admin = staff!(:admin, "admin")
    light = repo().get_by!(Role, slug: "light_agent")

    conn =
      visit(:put, "/support/admin/users/#{admin.id}/roles", admin, %{"role_ids" => [light.id]})

    assert redirected?(conn)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "own role management"
    assert "role.manage" in Permissions.list_slugs_for_user(admin)
  end
end
