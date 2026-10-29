defmodule Escalated.Plugs.EnforceRoutePermissions do
  @moduledoc """
  Requires the route's permission (`Escalated.RoutePermissions`) from the
  user's roles while roles & permissions is switched on
  (`Escalated.AccessFeatures`). Does nothing while it is off.

  Runs after `EnsureAdmin` / `EnsureAgent` (and `ApiAuthenticate` on the staff
  API, where the user is the token's owner), so the host gates still decide
  who reaches the area at all; this adds the permission on top. A route
  missing from the map is refused rather than let through. Failing answers
  403.
  """
  import Plug.Conn
  @behaviour Plug

  alias Escalated.RoutePermissions

  @unmapped "This route has no permission mapping."

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Escalated.AccessFeatures.roles_permissions?(), do: enforce(conn), else: conn
  end

  defp enforce(conn) do
    case check(conn) do
      :ok -> conn
      {:refuse, message} -> refuse(conn, message)
    end
  end

  defp check(conn) do
    with {:ok, user} <- user(conn),
         {:ok, controller, action} <- route(conn),
         {:ok, required} <- required(controller, action, params(conn)) do
      case required -- Escalated.Permissions.list_slugs_for_user(user) do
        [] -> :ok
        [slug | _] -> {:refuse, "You do not have the required permission: " <> slug}
      end
    end
  end

  defp user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:refuse, "Unauthorized."}
      user -> {:ok, user}
    end
  end

  defp required(controller, action, params) do
    case RoutePermissions.required(controller, action, params) do
      nil -> {:refuse, @unmapped}
      slugs -> {:ok, slugs}
    end
  end

  # The controller and action the router will dispatch to. Pipelines run
  # before the controller, so these are looked up rather than read from
  # conn.private.
  defp route(conn) do
    with router when not is_nil(router) <- conn.private[:phoenix_router],
         %{plug: controller, plug_opts: action} when is_atom(action) <-
           Phoenix.Router.route_info(router, conn.method, conn.path_info, conn.host) do
      {:ok, controller, action}
    else
      _ -> {:refuse, @unmapped}
    end
  end

  defp params(%Plug.Conn{params: %Plug.Conn.Unfetched{}}), do: %{}
  defp params(%Plug.Conn{params: params}), do: params

  defp refuse(conn, message) do
    conn
    |> put_status(403)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end
end
