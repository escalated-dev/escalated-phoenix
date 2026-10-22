defmodule Escalated.Controllers.PeoplePagesTest do
  @moduledoc """
  The people pages -- users and roles -- against the props the shared Vue
  pages read and the routes their forms post to (escalated-laravel's
  `UserController` and `RoleController`).
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{AgentProfile, Permission, Role, RolePermission}

  defp repo, do: Escalated.repo()

  setup do
    admin = host_user!(%{name: "Ada Admin", is_admin: true, is_agent: true})

    manage =
      repo().insert!(
        Permission.changeset(%Permission{}, %{
          slug: "tickets.manage",
          name: "Manage tickets",
          group: "Tickets"
        })
      )

    view =
      repo().insert!(
        Permission.changeset(%Permission{}, %{
          slug: "tickets.view",
          name: "View tickets",
          group: "Tickets"
        })
      )

    %{admin: admin, manage: manage, view: view}
  end

  defp permission_ids(role) do
    from(rp in RolePermission, where: rp.role_id == ^role.id, select: rp.permission_id)
    |> repo().all()
    |> Enum.sort()
  end

  test "Users/Index sends a paginator, the filters and the current user", %{admin: admin} do
    props = visit(:get, "/support/admin/users", admin) |> page!("Escalated/Admin/Users/Index")

    assert_keys(props, ~w(users filters currentUserId))
    [row | _] = assert_paginator(props["users"])
    assert_keys(row, ~w(id name email is_admin is_agent), "user")
    assert props["currentUserId"] == admin.id
  end

  test "Roles/Index lists roles with their user counts", %{admin: admin} do
    role = repo().insert!(Role.changeset(%Role{}, %{name: "Supervisor", slug: "supervisor"}))

    repo().insert!(%AgentProfile{user_id: admin.id, role: "supervisor", is_active: true})

    props = visit(:get, "/support/admin/roles", admin) |> page!("Escalated/Admin/Roles/Index")

    assert [row] = props["roles"]
    assert_keys(row, ~w(id name description is_system users_count), "role")
    assert row["id"] == role.id
    assert row["users_count"] == 1
  end

  test "Roles/Form gets permissions grouped, and the role with its permissions", ctx do
    props =
      visit(:get, "/support/admin/roles/create", ctx.admin) |> page!("Escalated/Admin/Roles/Form")

    assert %{"Tickets" => perms} = props["permissions"]
    assert_keys(hd(perms), ~w(id slug name group), "permission")

    role = repo().insert!(Role.changeset(%Role{}, %{name: "Lead", slug: "lead"}))
    repo().insert!(%RolePermission{role_id: role.id, permission_id: ctx.view.id})

    props =
      visit(:get, "/support/admin/roles/#{role.id}/edit", ctx.admin)
      |> page!("Escalated/Admin/Roles/Form")

    assert_keys(props["role"], ~w(id name description permissions), "role")
    assert Enum.map(props["role"]["permissions"], & &1["id"]) == [ctx.view.id]
  end

  test "store, update and destroy take the form's body", ctx do
    conn =
      visit(:post, "/support/admin/roles", ctx.admin, %{
        "name" => "Night Shift",
        "description" => "Overnight",
        "permissions" => [ctx.manage.id]
      })

    assert conn.status in [302, 303]
    assert location(conn) == "/support/admin/roles"
    role = repo().get_by!(Role, name: "Night Shift")
    assert role.slug == "night-shift"
    assert permission_ids(role) == [ctx.manage.id]

    conn =
      visit(:put, "/support/admin/roles/#{role.id}", ctx.admin, %{
        "name" => "Night Crew",
        "permissions" => [ctx.view.id]
      })

    assert conn.status in [302, 303]
    assert repo().get!(Role, role.id).name == "Night Crew"
    assert permission_ids(role) == [ctx.view.id]

    assert visit(:delete, "/support/admin/roles/#{role.id}", ctx.admin).status in [302, 303]
    assert repo().get(Role, role.id) == nil
    assert permission_ids(role) == []
  end

  test "a system role is not deleted", %{admin: admin} do
    role =
      repo().insert!(Role.changeset(%Role{}, %{name: "Admin", slug: "admin", is_system: true}))

    assert visit(:delete, "/support/admin/roles/#{role.id}", admin).status in [302, 303]
    assert repo().get(Role, role.id)
  end

  test "an unknown permission id is refused", %{admin: admin} do
    conn =
      visit(:post, "/support/admin/roles", admin, %{"name" => "Bad", "permissions" => [999_999]})

    assert conn.status in [302, 303]
    assert repo().get_by(Role, name: "Bad") == nil
  end
end
