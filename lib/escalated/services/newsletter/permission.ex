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

  def allowed?(user, permission) do
    check = Escalated.config(:newsletter_permission_check)

    cond do
      is_function(check, 2) ->
        check.(user, permission)

      admin_user?(user) ->
        true

      has_permission?(user, permission) ->
        true

      true ->
        false
    end
  end

  defp admin_user?(user) when not is_nil(user) do
    admin_check = Escalated.config(:admin_check)
    is_function(admin_check, 1) and admin_check.(user)
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
