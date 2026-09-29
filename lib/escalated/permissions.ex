defmodule Escalated.Permissions do
  @moduledoc """
  Shared staff authorization and permission slug resolution for the current user.
  """

  import Ecto.Query

  alias Escalated.Schemas.{AgentProfile, Permission, Role}

  @doc """
  Returns true when the user is an Escalated admin.

  Uses `:admin_check` when configured; otherwise falls back to host `is_admin`
  and `agent_profiles.role == "admin"`.
  """
  def admin?(user) do
    identified?(user) and authorized_admin?(user)
  end

  defp authorized_admin?(user) do
    case Escalated.config(:admin_check) do
      fun when is_function(fun, 1) ->
        fun.(user) == true

      nil ->
        host_flag?(user, :is_admin) or active_profile?(user, ["admin"])

      _ ->
        false
    end
  end

  @doc """
  Returns true for an identified agent. An explicit `:agent_check` is
  authoritative and must return true. Without one, effective admins, host
  agents and active agent/admin profiles can use agent surfaces.
  """
  def agent?(user), do: identified?(user) and authorized_agent?(user)

  defp authorized_agent?(user) do
    case Escalated.config(:agent_check) do
      fun when is_function(fun, 1) ->
        fun.(user) == true

      nil ->
        admin?(user) or host_flag?(user, :is_agent) or active_profile?(user, ["agent", "admin"])

      _ ->
        false
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
        on: ap.role == r.slug and ap.user_id == ^user_id and ap.is_active == true,
        select: p.slug,
        distinct: true,
        order_by: [asc: p.slug]
      )
      |> repo.all()
    else
      _ -> []
    end
  end

  defp host_flag?(user, key), do: truthy?(Map.get(user, key, Map.get(user, Atom.to_string(key))))

  defp active_profile?(user, roles) do
    with user_id when not is_nil(user_id) <- user_id(user),
         true <- rbac_tables_ready?() do
      repo = Escalated.repo()

      from(ap in AgentProfile,
        where: ap.user_id == ^user_id and ap.role in ^roles and ap.is_active == true,
        select: 1
      )
      |> repo.exists?()
    else
      _ -> false
    end
  end

  defp user_id(user) when is_map(user) do
    Map.get(user, :id, Map.get(user, "id"))
  end

  defp user_id(_), do: nil

  defp identified?(user) do
    case user_id(user) do
      id when is_integer(id) -> true
      id when is_binary(id) -> id != ""
      _ -> false
    end
  end

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
