defmodule Escalated.Plugs.EnsureAgent do
  @moduledoc """
  Plug that ensures the current user is an agent.

  Uses the `:agent_check` function configured in `:escalated` application config.
  The function receives the current user (from `conn.assigns.current_user`) and
  must return a boolean. Without a callback, host agent/admin flags or active
  Escalated agent profiles determine access through `Escalated.Permissions`.

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

    cond do
      is_nil(user) ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Authentication required"})
        |> halt()

      Escalated.Permissions.agent?(user) ->
        conn

      true ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "Agent access required"})
        |> halt()
    end
  end
end
