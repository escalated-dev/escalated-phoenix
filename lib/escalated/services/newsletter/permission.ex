defmodule Escalated.Services.Newsletter.Permission do
  @moduledoc false
  import Plug.Conn

  @manage "newsletters.manage"
  @send "newsletters.send"

  def require_manage!(conn), do: require!(conn, @manage)
  def require_send!(conn), do: require!(conn, @send)

  def require!(conn, permission) when is_binary(permission) do
    user = conn.assigns[:current_user]

    if allowed?(user, permission) do
      conn
    else
      conn
      |> put_status(403)
      |> Phoenix.Controller.json(%{error: "Insufficient permissions"})
      |> halt()
    end
  end

  def allowed?(nil, _permission), do: false

  def allowed?(user, permission) do
    check = Escalated.config(:newsletter_permission_check)

    cond do
      is_function(check, 2) ->
        check.(user, permission) == true

      not is_nil(check) ->
        false

      # Roles & permissions on: only the user's roles grant it, as on every
      # other screen (ADR 2026-10-29-configurable-access-features).
      Escalated.AccessFeatures.roles_permissions?() ->
        permission in Escalated.Permissions.list_slugs_for_user(user)

      admin_user?(user) ->
        true

      has_permission?(user, permission) ->
        true

      true ->
        false
    end
  end

  defp admin_user?(user) when not is_nil(user) do
    Escalated.Permissions.admin?(user)
  end

  defp admin_user?(_), do: false

  defp has_permission?(user, permission) when is_map(user) or is_struct(user) do
    perms =
      Map.get(user, :escalated_permissions) ||
        Map.get(user, :permissions) ||
        Map.get(user, "escalated_permissions") ||
        Map.get(user, "permissions") ||
        []

    permission in List.wrap(perms)
  end

  defp has_permission?(_, _), do: false
end
