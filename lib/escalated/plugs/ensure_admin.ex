defmodule Escalated.Plugs.EnsureAdmin do
  @moduledoc """
  Plug that ensures the current user is an admin.

  Uses the `:admin_check` function configured in `:escalated` application config.
  The function receives the current user (from `conn.assigns.current_user`) and
  must return a boolean.

  ## Configuration

      config :escalated,
        admin_check: &MyApp.Accounts.admin?/1
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = conn.assigns[:current_user]
    check_fn = Escalated.config(:admin_check)

    cond do
      is_nil(user) ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Authentication required"})
        |> halt()

      is_function(check_fn, 1) && check_fn.(user) ->
        conn

      is_nil(check_fn) ->
        conn

      true ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "Admin access required"})
        |> halt()
    end
  end
end
