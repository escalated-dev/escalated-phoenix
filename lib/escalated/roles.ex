defmodule Escalated.Roles do
  @moduledoc """
  Which users hold which Escalated roles (`role_user`). A user's permissions
  are the union of their roles' permissions
  (`Escalated.Permissions.list_slugs_for_user/1`), enforced while roles &
  permissions is switched on (`Escalated.AccessFeatures`).
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.Schemas.{Permission, Role, RolePermission, RoleUser}

  @doc "Gives the user the role with `slug`, keeping their other roles."
  def assign(user_id, slug) when is_binary(slug) do
    case repo().get_by(Role, slug: slug) do
      nil ->
        {:error, :unknown_role}

      role ->
        unless holds?(user_id, role.id), do: insert(user_id, role.id)
        {:ok, role}
    end
  end

  @doc """
  Gives the user found by `identifier` (email, then ID, in the host's user
  schema) the role with `slug`. Used by `mix escalated.roles.assign`.
  """
  def assign_to(identifier, slug) when is_binary(identifier) do
    case find_user(identifier) do
      nil -> {:error, :unknown_user}
      user -> assign(Map.get(user, :id), slug)
    end
  end

  @doc "The host user found by email, then by ID; nil when there is none."
  def find_user(identifier) do
    repo = Escalated.user_repo()
    schema = Escalated.user_schema()

    by_email =
      if :email in schema.__schema__(:fields),
        do: repo.one(from(u in schema, where: u.email == ^identifier, limit: 1))

    by_email || repo.get(schema, identifier)
  rescue
    Ecto.Query.CastError -> nil
  end

  @doc """
  Replaces the user's roles with `role_ids`. Returns `{:error, :unknown_role}`
  when any id is not a role.
  """
  def replace(user_id, role_ids) when is_list(role_ids) do
    ids = Enum.uniq(role_ids)

    known =
      if ids == [],
        do: [],
        else: from(r in Role, where: r.id in ^ids, select: r.id) |> repo().all()

    if length(known) == length(ids) do
      repo().transaction(fn ->
        from(ru in RoleUser, where: ru.user_id == ^user_id) |> repo().delete_all()
        Enum.each(ids, &insert(user_id, &1))
      end)

      :ok
    else
      {:error, :unknown_role}
    end
  end

  @doc "Whether any of the roles grants `slug`."
  def grants?([], _slug), do: false

  def grants?(role_ids, slug) do
    from(rp in RolePermission,
      join: p in Permission,
      on: p.id == rp.permission_id,
      where: rp.role_id in ^role_ids and p.slug == ^slug,
      select: 1
    )
    |> repo().exists?()
  end

  @doc "`%{user_id => [role slug]}` for the given users."
  def slugs_by_user([]), do: %{}

  def slugs_by_user(user_ids) do
    from(ru in RoleUser,
      join: r in Role,
      on: r.id == ru.role_id,
      where: ru.user_id in ^user_ids,
      order_by: [asc: r.slug],
      select: {ru.user_id, r.slug}
    )
    |> repo().all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  @doc "Every role as `%{id, name, slug}`, by name."
  def options do
    from(r in Role, order_by: [asc: r.name], select: %{id: r.id, name: r.name, slug: r.slug})
    |> repo().all()
  end

  defp holds?(user_id, role_id) do
    from(ru in RoleUser, where: ru.user_id == ^user_id and ru.role_id == ^role_id, select: 1)
    |> repo().exists?()
  end

  defp insert(user_id, role_id) do
    repo().insert!(%RoleUser{
      role_id: role_id,
      user_id: user_id,
      tenant_id: Escalated.Tenancy.current_id!()
    })
  end

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())
end
