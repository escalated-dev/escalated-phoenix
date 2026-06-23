defmodule Escalated.Permissions do
  @moduledoc """
  RBAC helpers: admin detection and permission slug resolution for the current user.
  """

  import Ecto.Query

  alias Escalated.Schemas.{AgentProfile, Permission, Role}

  @doc """
  Returns true when the user is an Escalated admin.

  Uses `:admin_check` when configured; otherwise falls back to host `is_admin`
  and `agent_profiles.role == "admin"`.
  """
  def admin?(nil), do: false

  def admin?(user) do
    case Escalated.config(:admin_check) do
      fun when is_function(fun, 1) ->
        fun.(user)

      _ ->
        host_admin?(user) || agent_profile_admin?(user)
    end
  end

  @doc """
  Permission slugs granted to the user via their agent profile role.

  Returns `[]` when there is no user, RBAC tables are absent, or the user has no profile.
  """
  def list_slugs_for_user(nil), do: []

  def list_slugs_for_user(user) do
    with user_id when not is_nil(user_id) <- user_id(user),
         true <- rbac_tables_ready?() do
      repo = Escalated.repo()

      from(p in Permission,
        join: rp in ^role_permissions_table(),
        on: rp.permission_id == p.id,
        join: r in Role,
        on: r.id == rp.role_id,
        join: ap in AgentProfile,
        on: ap.role == r.slug and ap.user_id == ^user_id,
        select: p.slug,
        distinct: true,
        order_by: [asc: p.slug]
      )
      |> repo.all()
    else
      _ -> []
    end
  end

  defp host_admin?(user) when is_map(user) do
    truthy?(Map.get(user, :is_admin)) || truthy?(Map.get(user, "is_admin"))
  end

  defp host_admin?(_), do: false

  defp agent_profile_admin?(user) do
    with user_id when not is_nil(user_id) <- user_id(user),
         true <- rbac_tables_ready?() do
      repo = Escalated.repo()

      from(ap in AgentProfile,
        where: ap.user_id == ^user_id and ap.role == "admin",
        select: 1
      )
      |> repo.exists?()
    else
      _ -> false
    end
  end

  defp user_id(user) when is_map(user) do
    Map.get(user, :id) || Map.get(user, "id")
  end

  defp user_id(_), do: nil

  defp truthy?(value), do: value in [true, 1, "1", "true"]

  defp rbac_tables_ready? do
    repo = Escalated.repo()
    roles = Escalated.table_name("roles")

    case Ecto.Adapters.SQL.query(repo, "SELECT 1 FROM #{roles} LIMIT 0", []) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp role_permissions_table, do: Escalated.table_name("role_permissions")
end
