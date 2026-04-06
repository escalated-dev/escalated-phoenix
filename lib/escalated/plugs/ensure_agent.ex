defmodule Escalated.Plugs.EnsureAgent do
  @moduledoc """
  Plug that ensures the current user is an agent.

  Uses the `:agent_check` function configured in `:escalated` application config.
  The function receives the current user (from `conn.assigns.current_user`) and
  must return a boolean.

  ## Configuration

      config :escalated,
        agent_check: &MyApp.Accounts.agent?/1
  """
  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user = conn.assigns[:current_user]
    check_fn = Escalated.config(:agent_check)

    cond do
      is_nil(user) ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Authentication required"})
        |> halt()

      is_function(check_fn, 1) && check_fn.(user) ->
        conn

      is_nil(check_fn) ->
        # If no check function configured, allow through (developer must configure)
        conn

      true ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "Agent access required"})
        |> halt()
    end
  end
end
