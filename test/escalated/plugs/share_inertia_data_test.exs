defmodule Escalated.Plugs.ShareInertiaDataTest do
  use ExUnit.Case, async: false
  use Escalated.DataCase

  alias Escalated.Permissions
  alias Escalated.Plugs.ShareInertiaData
  alias Escalated.Schemas.{AgentProfile, Permission, Role}
  alias Escalated.TestRepo

  setup do
    prev_admin_check = Application.get_env(:escalated, :admin_check)
    on_exit(fn -> restore_admin_check(prev_admin_check) end)
    Application.delete_env(:escalated, :admin_check)
    :ok
  end

  describe "escalated_props/2" do
    test "returns is_admin false and empty permissions without a user" do
      props = ShareInertiaData.escalated_props(nil, Escalated.configuration())

      assert props.is_admin == false
      assert props.permissions == []
    end

    test "returns is_admin and permissions for an agent profile role" do
      admin_role = insert_role!(slug: "admin", name: "Admin")
      manage = insert_permission!(slug: "newsletters.manage", name: "Manage newsletters")
      send_perm = insert_permission!(slug: "newsletters.send", name: "Send newsletters")

      link_role_permissions!(admin_role, [manage, send_perm])

      user = %{id: 42, email: "agent@example.com", name: "Agent"}
      insert_agent_profile!(user_id: user.id, role: "admin")

      props = ShareInertiaData.escalated_props(user, Escalated.configuration())

      assert props.is_admin == true
      assert props.permissions == ["newsletters.manage", "newsletters.send"]
    end

    test "uses admin_check when configured" do
      Application.put_env(:escalated, :admin_check, fn user -> user.id == 7 end)

      user = %{id: 7, is_admin: false}
      props = ShareInertiaData.escalated_props(user, Escalated.configuration())

      assert props.is_admin == true
      assert props.permissions == []
    end

    test "host is_admin without agent profile" do
      user = %{id: 99, is_admin: true, is_agent: true}

      props = ShareInertiaData.escalated_props(user, Escalated.configuration())

      assert props.is_admin == true
      assert props.permissions == []
    end
  end

  describe "Permissions.list_slugs_for_user/1" do
    test "returns slugs only for the user's role" do
      agent_role = insert_role!(slug: "agent", name: "Agent")
      manage = insert_permission!(slug: "newsletters.manage", name: "Manage newsletters")
      _send_perm = insert_permission!(slug: "newsletters.send", name: "Send newsletters")

      link_role_permissions!(agent_role, [manage])
      insert_agent_profile!(user_id: 1, role: "agent")

      assert Permissions.list_slugs_for_user(%{id: 1}) == ["newsletters.manage"]
    end
  end

  defp restore_admin_check(nil), do: Application.delete_env(:escalated, :admin_check)
  defp restore_admin_check(value), do: Application.put_env(:escalated, :admin_check, value)

  defp insert_role!(attrs) do
    defaults = %{name: "Role", slug: "role-#{System.unique_integer()}"}

    %Role{}
    |> Role.changeset(Map.merge(defaults, Map.new(attrs)))
    |> TestRepo.insert!()
  end

  defp insert_permission!(attrs) do
    defaults = %{name: "Permission", slug: "perm-#{System.unique_integer()}"}

    %Permission{}
    |> Permission.changeset(Map.merge(defaults, Map.new(attrs)))
    |> TestRepo.insert!()
  end

  defp link_role_permissions!(role, permissions) do
    table = Escalated.table_name("role_permissions")

    for permission <- permissions do
      TestRepo.insert_all(table, [
        %{role_id: role.id, permission_id: permission.id}
      ])
    end
  end

  defp insert_agent_profile!(attrs) do
    defaults = %{user_id: 1, role: "agent", display_name: "Agent"}

    %AgentProfile{}
    |> AgentProfile.changeset(Map.merge(defaults, Map.new(attrs)))
    |> TestRepo.insert!()
  end
end
