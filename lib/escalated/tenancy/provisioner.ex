defmodule Escalated.Tenancy.Provisioner do
  @moduledoc """
  Idempotent permission and default-role provisioning in the current tenant.

  Call `seed/0` inside `Tenancy.run/2` after the host creates a merchant (or
  run `mix escalated.seed_permissions`). It upserts every permission in
  `Escalated.Permissions.Catalog` and the system roles `admin`, `agent` and
  `light_agent`. The admin role receives every permission; the agent and
  light agent roles receive their catalog defaults on top of whatever they
  already grant. Existing grants and custom roles are preserved.

  This creates no staff membership, assigns no roles and adopts no legacy
  rows. Give users roles with `mix escalated.roles.assign` or the admin users
  page.
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

      permissions = repo.all(Permission)
      slugs = Enum.map(permissions, & &1.slug)

      Enum.each(Catalog.roles(), fn definition ->
        role =
          repo
          |> upsert(
            Role,
            Map.take(definition, [:slug, :name, :description]) |> Map.put(:is_system, true)
          )
          |> repo.preload(:permissions)

        wanted = Catalog.expand(definition.permissions, slugs)

        grants =
          (role.permissions ++ Enum.filter(permissions, &(&1.slug in wanted)))
          |> Enum.uniq_by(& &1.id)

        role
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:permissions, grants)
        |> repo.update!()
      end)

      %{permissions: length(Catalog.all()), roles: length(Catalog.roles())}
    end)
  end

  defp upsert(repo, schema, attrs) do
    case repo.get_by(schema, slug: attrs.slug) do
      nil -> schema |> struct() |> schema.changeset(attrs) |> repo.insert!()
      row -> row |> schema.changeset(attrs) |> repo.update!()
    end
  end
end
