defmodule Mix.Tasks.Escalated.SeedPermissions do
  @shortdoc "Seeds Escalated permissions and default roles in selected tenants"
  @moduledoc """
  Seeds the permission catalog and default admin/agent roles idempotently.

      mix escalated.seed_permissions --tenant merchant-id

  With tenancy enabled and no `--tenant`, the trusted resolver's `tenants/0`
  catalog selects the merchants. Legacy single-tenant hosts need no selector.
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    Escalated.Tenancy.Maintenance.run(args, fn _remaining ->
      {:ok, counts} = Escalated.Tenancy.Provisioner.seed()

      Mix.shell().info(
        "Escalated: seeded #{counts.permissions} permission(s) and #{counts.roles} default role(s)."
      )
    end)
  end
end
