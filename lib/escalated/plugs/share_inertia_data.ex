defmodule Escalated.Plugs.ShareInertiaData do
  @moduledoc """
  Plug that shares common Escalated data with Inertia.js pages.

  Only active when `inertia_phoenix` is loaded and `ui_enabled` is true.
  Shares the current user, escalated configuration, and flash messages.
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    config = Escalated.configuration()

    unless Escalated.Config.ui_enabled?(config) do
      conn
    else
      if Code.ensure_loaded?(InertiaPhoenix) do
        share_data(conn, config)
      else
        conn
      end
    end
  end

  defp share_data(conn, config) do
    user = conn.assigns[:current_user]

    shared = %{
      escalated: %{
        route_prefix: config.route_prefix,
        allow_customer_close: config.allow_customer_close,
        priorities: Escalated.Schemas.Ticket.priorities(),
        statuses: Escalated.Schemas.Ticket.statuses()
      },
      auth: %{
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
    }

    Plug.Conn.assign(conn, :inertia_shared, shared)
  end
end
