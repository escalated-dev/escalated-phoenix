defmodule Escalated.Tenancy.Provisioner do
  @moduledoc """
  Idempotent permission and default-role provisioning in the current tenant.

  Call `seed/0` inside `Tenancy.run/2` after the host creates a merchant. The
  admin role receives all tenant permissions. New agent roles start without
  elevated permissions: today's catalog contains only newsletter management
  and sending. Existing agent grants and custom roles are preserved.

  This creates no staff membership and adopts no legacy rows. The host must
  explicitly provision its tenant membership and active agent/admin profiles.
  """

  alias Escalated.Permissions.Catalog
  alias Escalated.Schemas.{Permission, Role}
  alias Escalated.Tenancy

  def seed do
    Tenancy.current_id!()
    repo = Escalated.repo()

    repo.transaction(fn ->
      Enum.each(Catalog.all(), fn attrs ->
        upsert(repo, Permission, attrs)
      end)

      admin = upsert(repo, Role, %{slug: "admin", name: "Admin", is_system: true})
      upsert(repo, Role, %{slug: "agent", name: "Agent", is_system: true})

      admin
      |> repo.preload(:permissions)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:permissions, repo.all(Permission))
      |> repo.update!()

      %{permissions: length(Catalog.all()), roles: 2}
    end)
  end

  defp upsert(repo, schema, attrs) do
    case repo.get_by(schema, slug: attrs.slug) do
      nil -> schema |> struct() |> schema.changeset(attrs) |> repo.insert!()
      row -> row |> schema.changeset(attrs) |> repo.update!()
    end
  end
end
