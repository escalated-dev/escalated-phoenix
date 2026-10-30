defmodule Escalated.Sso.UserResolver do
  @moduledoc """
  Maps an SSO identity to a host user (ADR
  2026-10-29-configurable-access-features):

  - matched by email, case-insensitively, in the host's user schema;
  - no match: refused, unless `sso: [create_users: true]`
    (`ESCALATED_SSO_CREATE_USERS`), which creates one with that email and
    name and no password. The host's `sso: [create_user: {Mod, :fun}]`
    callback, given `%{email, name}` and returning `{:ok, user}`, does the
    creating when set; otherwise the user schema is inserted with `email`
    (and `name`, when it has one) and nothing else, so it has no usable
    password;
  - with roles & permissions on and `sso: [sync_roles: true]`
    (`ESCALATED_SSO_SYNC_ROLES`), a role naming an existing Escalated role
    slug replaces the user's roles. An unknown value changes nothing.

  SSO never grants the host's admin or agent gate; it only signs the user in.
  """
  import Ecto.Query, only: [from: 2]

  alias Escalated.{AccessFeatures, Roles, Sso}
  alias Escalated.Schemas.Role

  @doc "`{:ok, user}` or `{:error, reason}` (for the log)."
  def resolve(%{email: email} = identity) do
    with {:ok, user} <- find_or_create(email, identity) do
      sync_role(user, identity.role)
      {:ok, user}
    end
  end

  defp find_or_create(email, identity) do
    case find(email) do
      nil ->
        if Sso.option(:create_users),
          do: create(identity),
          else: {:error, "no user has the email #{email} and create_users is off"}

      user ->
        {:ok, user}
    end
  end

  defp find(email) do
    schema = Escalated.user_schema()

    if :email in schema.__schema__(:fields) do
      lowered = String.downcase(email)

      from(u in schema, where: fragment("lower(?)", u.email) == ^lowered, limit: 1)
      |> Escalated.user_repo().one()
    end
  end

  defp create(%{email: email, name: name}) do
    name = if String.trim(name) == "", do: email |> String.split("@") |> hd(), else: name

    case Sso.create_user_callback() do
      nil -> insert(email, name)
      {module, function} -> apply(module, function, [%{email: email, name: name}])
      fun when is_function(fun, 1) -> fun.(%{email: email, name: name})
    end
    |> case do
      {:ok, user} -> {:ok, user}
      other -> {:error, "could not create a user for #{email}: #{inspect(other)}"}
    end
  end

  defp insert(email, name) do
    schema = Escalated.user_schema()
    fields = schema.__schema__(:fields)

    attrs =
      %{email: email}
      |> then(&if(:name in fields, do: Map.put(&1, :name, name), else: &1))

    schema
    |> struct()
    |> Ecto.Changeset.change(attrs)
    |> Escalated.user_repo().insert()
  end

  defp sync_role(_user, ""), do: :ok

  defp sync_role(user, slug) do
    if AccessFeatures.roles_permissions?() and Sso.option(:sync_roles) do
      case Escalated.repo().get_by(Role, slug: slug) do
        nil -> :ok
        role -> Roles.replace(Map.get(user, :id), [role.id])
      end
    else
      :ok
    end
  end
end
