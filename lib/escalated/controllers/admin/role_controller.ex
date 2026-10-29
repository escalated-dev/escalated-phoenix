defmodule Escalated.Controllers.Admin.RoleController do
  @moduledoc """
  Admin CRUD over roles and the permissions they grant, serving
  `Escalated/Admin/Roles/Index` and `Escalated/Admin/Roles/Form` with the props
  escalated-laravel's `RoleController` sends.

  A role's users are the `role_user` rows holding it, which is how
  `Escalated.Permissions.list_slugs_for_user/1` resolves permissions. System
  roles cannot be deleted. The routes are mounted only while roles &
  permissions is switched on (`Escalated.AccessFeatures`).
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  import Ecto.Query, only: [from: 2]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Schemas.{Permission, Role, RolePermission, RoleUser}

  def index(conn, _params) do
    counts =
      from(ru in RoleUser,
        group_by: ru.role_id,
        select: {ru.role_id, count(ru.user_id)}
      )
      |> repo().all()
      |> Map.new()

    roles =
      from(r in Role, order_by: [asc: r.name])
      |> repo().all()
      |> Enum.map(&Map.put(role_json(&1), :users_count, Map.get(counts, &1.id, 0)))

    UIRenderer.render_page(conn, "Escalated/Admin/Roles/Index", %{roles: roles})
  end

  def new(conn, _params) do
    UIRenderer.render_page(conn, "Escalated/Admin/Roles/Form", %{
      role: nil,
      permissions: grouped_permissions()
    })
  end

  def edit(conn, %{"id" => id}) do
    case repo().get(Role, id) do
      nil ->
        not_found(conn)

      role ->
        UIRenderer.render_page(conn, "Escalated/Admin/Roles/Form", %{
          role:
            Map.put(
              role_json(role),
              :permissions,
              Enum.map(permissions_of(role), &permission_json/1)
            ),
          permissions: grouped_permissions()
        })
    end
  end

  def create(conn, params) do
    attrs = %{
      "name" => params["name"],
      "description" => params["description"],
      "slug" => slugify(params["name"])
    }

    save(conn, %Role{}, attrs, params["permissions"], index_path() <> "/create", "Role created.")
  end

  def update(conn, %{"id" => id} = params) do
    case repo().get(Role, id) do
      nil ->
        not_found(conn)

      role ->
        attrs = %{"name" => params["name"], "description" => params["description"]}

        save(
          conn,
          role,
          attrs,
          params["permissions"] || [],
          "#{index_path()}/#{id}/edit",
          "Role updated."
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    case repo().get(Role, id) do
      nil ->
        not_found(conn)

      %Role{is_system: true} ->
        conn |> put_flash(:error, "System roles cannot be deleted.") |> redirect(to: index_path())

      role ->
        repo().transaction(fn ->
          from(rp in RolePermission, where: rp.role_id == ^role.id) |> repo().delete_all()
          from(ru in RoleUser, where: ru.role_id == ^role.id) |> repo().delete_all()
          repo().delete!(role)
        end)

        conn |> put_flash(:info, "Role deleted.") |> redirect(to: index_path())
    end
  end

  # Saves the role and replaces its permissions in one transaction. A nil
  # permission list (a create without the key) grants nothing.
  defp save(conn, role, attrs, permission_ids, back, message) do
    with {:ok, ids} <- permission_ids(permission_ids),
         {:ok, _role} <- persist(role, attrs, ids) do
      conn |> put_flash(:info, message) |> redirect(to: index_path())
    else
      {:error, %Ecto.Changeset{} = changeset} -> FormResponse.invalid(conn, changeset, back)
      {:error, errors} when is_map(errors) -> FormResponse.invalid(conn, errors, back)
    end
  end

  defp persist(role, attrs, ids) do
    repo().transaction(fn ->
      case role |> Role.changeset(attrs) |> repo().insert_or_update() do
        {:ok, saved} ->
          from(rp in RolePermission, where: rp.role_id == ^saved.id) |> repo().delete_all()

          tenant_id = Escalated.Tenancy.current_id!()

          Enum.each(ids, fn id ->
            repo().insert!(%RolePermission{
              role_id: saved.id,
              permission_id: id,
              tenant_id: tenant_id
            })
          end)

          saved

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  defp permission_ids(nil), do: {:ok, []}

  defp permission_ids(ids) when is_list(ids) do
    parsed = Enum.map(ids, &parse_id/1)

    known =
      case Enum.reject(parsed, &is_nil/1) do
        [] -> []
        valid -> from(p in Permission, where: p.id in ^valid, select: p.id) |> repo().all()
      end

    if Enum.all?(parsed, &(&1 in known)),
      do: {:ok, Enum.uniq(parsed)},
      else: {:error, %{permissions: ["contains an unknown permission"]}}
  end

  defp permission_ids(_), do: {:error, %{permissions: ["must be a list"]}}

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(_), do: nil

  defp permissions_of(role) do
    from(p in Permission,
      join: rp in RolePermission,
      on: rp.permission_id == p.id,
      where: rp.role_id == ^role.id,
      order_by: [asc: p.id]
    )
    |> repo().all()
  end

  defp grouped_permissions do
    from(p in Permission, order_by: [asc: p.group, asc: p.slug])
    |> repo().all()
    |> Enum.group_by(&(&1.group || "General"), &permission_json/1)
  end

  defp role_json(r) do
    %{
      id: r.id,
      name: r.name,
      slug: r.slug,
      description: r.description,
      is_system: r.is_system,
      created_at: r.inserted_at && DateTime.to_iso8601(r.inserted_at)
    }
  end

  defp permission_json(p),
    do: %{id: p.id, slug: p.slug, name: p.name, group: p.group, description: p.description}

  defp slugify(nil), do: nil

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp not_found(conn), do: conn |> put_status(404) |> json(%{error: "Role not found"})

  defp repo, do: Escalated.Tenancy.scoped_repo(Escalated.repo())

  defp index_path, do: Escalated.config(:route_prefix, "/support") <> "/admin/roles"
end
