defmodule Escalated.Plugs.EnsureAgent do
  @moduledoc """
  Plug that ensures the current user is an agent.

  Uses the `:agent_check` function configured in `:escalated` application config.
  The function receives the current user (from `conn.assigns.current_user`) and
  must return a boolean. Without a callback, host agent/admin flags or active
  Escalated agent profiles determine access through `Escalated.Permissions`.

  A signed-in `current_user` that is not a struct or map with an `:id`
  raises `Escalated.UserContract.Error`, which names what to configure.

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

    # A signed-in user Escalated cannot identify is a setup mistake, not a
    # refusal: say what to configure (Escalated.UserContract).
    Escalated.UserContract.check_current_user!(user)

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
