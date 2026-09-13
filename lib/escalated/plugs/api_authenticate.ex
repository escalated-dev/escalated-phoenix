defmodule Escalated.Plugs.ApiAuthenticate do
  @moduledoc """
  Resolves the caller of the JSON ticket API and refuses anonymous requests.

  The ticket endpoints under `/api/v1` read and change any ticket, so they need
  a known caller before `Escalated.Plugs.EnsureAgent` can decide whether that
  caller is an agent. The caller comes from, in order:

    1. `conn.assigns.current_user`, when the host's own pipeline has already
       authenticated the request (a session, or the host's own token plug).
    2. An `Authorization: Bearer <token>` header, validated by the host's
       `:api_token_validator` callback (see `Escalated.Api.HostAuth`). The user
       it returns is assigned as `:current_user`.

  Anything else -- no header, a token the validator rejects, or no validator
  configured -- is answered 401 and halted.

  ## Configuration

      config :escalated,
        api_token_validator: &MyApp.api_validate_token/1,
        agent_check: &MyApp.Accounts.agent?/1
  """
  import Plug.Conn
  @behaviour Plug

  alias Escalated.Api.HostAuth

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{assigns: %{current_user: user}} = conn, _opts) when not is_nil(user),
    do: conn

  def call(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, user} <- HostAuth.validate(token) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "Authentication required"})
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" -> {:ok, token}
      _ -> :error
    end
  end
end
