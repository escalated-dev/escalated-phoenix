defmodule Escalated.Plugs.ShareInertiaData do
  @moduledoc """
  Plug that shares common Escalated data with Inertia.js pages.

  Only active when `inertia` is loaded and `ui_enabled` is true.
  Shares the current user, escalated configuration, and flash messages.
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config = Escalated.configuration()

    if Escalated.Config.ui_enabled?(config) do
      if Code.ensure_loaded?(Inertia.Controller) do
        share_data(conn, config)
      else
        conn
      end
    else
      conn
    end
  end

  @doc false
  def escalated_props(user, config) do
    %{
      route_prefix: config.route_prefix,
      allow_customer_close: config.allow_customer_close,
      priorities: Escalated.Schemas.Ticket.priorities(),
      statuses: Escalated.Schemas.Ticket.statuses(),
      is_admin: Escalated.Permissions.admin?(user),
      permissions: Escalated.Permissions.list_slugs_for_user(user),
      features: %{
        newsletters: newsletters_enabled?()
      }
    }
  end

  defp share_data(conn, config) do
    user = conn.assigns[:current_user]

    auth = %{
      user:
        if user do
          %{
            id: user.id,
            email: if(Map.has_key?(user, :email), do: user.email, else: nil),
            name: if(Map.has_key?(user, :name), do: user.name, else: nil)
          }
        else
          nil
        end
    }

    # assign_prop/3, not Plug.Conn.assign/3. The retired adapter read shared
    # data out of conn.assigns; `inertia` reads it from conn.private, so an
    # assign would leave every page missing its shared props with no error.
    conn
    |> assign_inertia_prop(:escalated, escalated_props(user, config))
    |> assign_inertia_prop(:auth, auth)
  end

  # apply/3 rather than a direct call because `inertia` is an OPTIONAL
  # dependency: a direct call compiles to a warning for hosts that do not
  # install it, which is why the caller guards on Code.ensure_loaded?/1.
  defp assign_inertia_prop(conn, key, value) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(Inertia.Controller, :assign_prop, [conn, key, value])
  end

  defp newsletters_enabled? do
    Application.get_env(:escalated, :enable_newsletters, false) in [true, "true", 1, "1"]
  end
end
