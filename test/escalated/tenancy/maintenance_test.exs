defmodule Escalated.Tenancy.MaintenanceTest do
  use Escalated.DataCase, async: false

  alias Escalated.Schemas.{AgentProfile, EscalatedSetting, Permission, Role, RolePermission}
  alias Escalated.Services.GeneralSettings
  alias Escalated.Tenancy
  alias Escalated.Tenancy.{Maintenance, Provisioner}
  alias Escalated.TestRepo

  defmodule Resolver do
    def tenants, do: Process.get(:catalog_tenants, ["merchant-a", "merchant-b"])
  end

  defmodule WithoutCatalog do
  end

  setup do
    previous =
      Map.new([:tenancy_enabled, :tenant_resolver], &{&1, Application.fetch_env(:escalated, &1)})

    Application.put_env(:escalated, :tenancy_enabled, true)
    Application.put_env(:escalated, :tenant_resolver, Resolver)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:escalated, key, value)
        {key, :error} -> Application.delete_env(:escalated, key)
      end)
    end)

    :ok
  end

  test "the trusted catalog scopes each maintenance operation and restores the caller" do
    Process.put(:catalog_tenants, ["merchant-a", "merchant-b", "merchant-a"])

    result =
      Tenancy.run("outer", fn ->
        result =
          Maintenance.run(["--dry-run"], fn args ->
            repo = Escalated.repo()

            repo.insert!(
              EscalatedSetting.changeset(%EscalatedSetting{}, %{key: "maintenance", value: "done"})
            )

            assert repo.aggregate(EscalatedSetting, :count) == 1
            {Tenancy.current_id!(), args}
          end)

        assert Tenancy.current_id!() == "outer"
        result
      end)

    assert result == [
             {"merchant-a", {"merchant-a", ["--dry-run"]}},
             {"merchant-b", {"merchant-b", ["--dry-run"]}}
           ]

    assert TestRepo.aggregate(EscalatedSetting, :count) == 2
    assert_raise Tenancy.Error, fn -> Tenancy.current_id!() end
  end

  test "an explicit tenant preserves other CLI flags and does not require a catalog" do
    Application.put_env(:escalated, :tenant_resolver, WithoutCatalog)
    callback = fn args -> {Tenancy.current_id!(), args} end

    assert Maintenance.run(
             ["--warn-minutes", "60", "--tenant", "merchant-a", "--dry-run"],
             callback
           ) ==
             [{"merchant-a", {"merchant-a", ["--warn-minutes", "60", "--dry-run"]}}]

    assert Maintenance.run(["--tenant=merchant-b"], callback) == [
             {"merchant-b", {"merchant-b", []}}
           ]

    assert_raise Tenancy.Error, fn -> Maintenance.run([], callback) end
    assert_raise ArgumentError, fn -> Maintenance.run(["--tenant"], callback) end

    assert_raise ArgumentError, fn ->
      Maintenance.run(["--tenant", "a", "--tenant", "b"], callback)
    end
  end

  test "every catalog identity is validated before work starts and failures restore context" do
    Process.put(:catalog_tenants, ["merchant-a", ""])

    assert_raise Tenancy.Error, fn ->
      Maintenance.run([], fn _ -> flunk("invalid catalogs must not perform partial work") end)
    end

    Process.put(:catalog_tenants, ["merchant-a"])

    Tenancy.run("outer", fn ->
      error =
        assert_raise Maintenance.Error, fn ->
          Maintenance.run([], fn _ -> raise "failed worker" end)
        end

      assert [{"merchant-a", %RuntimeError{message: "failed worker"}}] = error.failures
      assert Tenancy.current_id!() == "outer"
    end)

    assert_raise Tenancy.Error, fn -> Tenancy.current_id!() end
  end

  test "a failing tenant is logged and the sweep still reaches every other tenant" do
    Process.put(:catalog_tenants, ["merchant-a", "merchant-b", "merchant-c"])
    test = self()

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        error =
          assert_raise Maintenance.Error, ~r/2 tenant\(s\): merchant-a, merchant-c/, fn ->
            Maintenance.run([], fn _ ->
              tenant = Tenancy.current_id!()
              send(test, {:ran, tenant})

              case tenant do
                "merchant-a" -> raise "row payload secret-value"
                "merchant-c" -> exit(:worker_down)
                _ -> :ok
              end
            end)
          end

        assert [{"merchant-a", %RuntimeError{}}, {"merchant-c", :worker_down}] = error.failures
      end)

    for tenant <- ["merchant-a", "merchant-b", "merchant-c"], do: assert_received({:ran, ^tenant})
    assert log =~ "tenant merchant-a: error RuntimeError"
    assert log =~ "tenant merchant-c: exit"
    refute log =~ "secret-value"
    assert_raise Tenancy.Error, fn -> Tenancy.current_id!() end
  end

  test "legacy mode runs once and refuses a misleading tenant selector" do
    Application.put_env(:escalated, :tenancy_enabled, false)

    assert Maintenance.run(["--dry-run"], fn args -> {Tenancy.current_id!(), args} end) ==
             [{"", {"", ["--dry-run"]}}]

    assert_raise ArgumentError, fn -> Maintenance.run(["--tenant=a"], fn _ -> :ok end) end
  end

  test "general settings upserts update only the current merchant's key" do
    for tenant <- ["merchant-a", "merchant-b"] do
      Tenancy.run(tenant, fn ->
        assert {:ok, _} = GeneralSettings.update(%{"show_powered_by" => true})
      end)
    end

    Tenancy.run("merchant-a", fn ->
      assert {:ok, _} = GeneralSettings.update(%{"show_powered_by" => false})
      refute GeneralSettings.enabled?(:show_powered_by)
      assert Escalated.repo().aggregate(EscalatedSetting, :count) == 1
    end)

    Tenancy.run("merchant-b", fn -> assert GeneralSettings.enabled?(:show_powered_by) end)
    assert TestRepo.aggregate(EscalatedSetting, :count) == 2
  end

  test "provisioning is tenant-local and idempotent, without creating staff membership" do
    for tenant <- ["merchant-a", "merchant-b"] do
      Tenancy.run(tenant, fn ->
        assert {:ok, %{roles: 2, permissions: count}} = Provisioner.seed()
        assert count == length(Escalated.Permissions.Catalog.all())
        assert {:ok, _} = Provisioner.seed()

        repo = Escalated.repo()
        admin = repo.get_by!(Role, slug: "admin") |> repo.preload(:permissions)
        agent = repo.get_by!(Role, slug: "agent") |> repo.preload(:permissions)
        assert length(admin.permissions) == count
        assert agent.permissions == []

        permission = hd(admin.permissions)

        repo.insert!(
          Ecto.Changeset.change(%RolePermission{},
            role_id: agent.id,
            permission_id: permission.id
          )
        )

        assert {:ok, _} = Provisioner.seed()
        assert [kept] = repo.preload(agent, :permissions).permissions
        assert kept.id == permission.id
      end)
    end

    assert TestRepo.aggregate(Role, :count) == 4

    assert TestRepo.aggregate(Permission, :count) ==
             2 * length(Escalated.Permissions.Catalog.all())

    assert TestRepo.aggregate(AgentProfile, :count) == 0
  end
end
