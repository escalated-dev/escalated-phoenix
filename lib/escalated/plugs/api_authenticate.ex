defmodule Escalated.Plugs.ApiAuthenticate do
  @moduledoc """
  Resolves the caller of the JSON ticket API and refuses anonymous requests.

  The ticket endpoints under `/api/v1` read and change any ticket, so they need
  a known caller before `Escalated.Plugs.EnsureAgent` can decide whether that
  caller is an agent. The caller comes from, in order:

    1. An `Authorization: Bearer <token>` header carrying an Escalated API
       token (`Escalated.Schemas.ApiToken`, issued on the admin API tokens
       page), when the host has turned them on with
       `config :escalated, api_tokens_enabled: true`. The request acts as the
       token's owner. It is refused 401 when the token has expired or its
       owner no longer exists, and 403 when the token lacks the `agent`
       ability (an `admin`-only token); an owner who is no longer an agent is
       refused 403 by `EnsureAgent`.
    2. Any other bearer token, validated by the host's `:api_token_validator`
       callback (see `Escalated.Api.HostAuth`). The user it returns is assigned
       as `:current_user`. A bearer value Escalated did not issue always takes
       this path, so hosts that authenticate the API with their own tokens keep
       working with Escalated tokens turned on.
    3. `conn.assigns.current_user`, when there is no bearer header and the
       host's own pipeline has already authenticated the request.

  Anything else -- no caller, a token the validator rejects, or no validator
  configured -- is answered 401 and halted.

  ## Configuration

      config :escalated,
        api_tokens_enabled: true,
        api_token_validator: &MyApp.api_validate_token/1,
        agent_check: &MyApp.Accounts.agent?/1
  """
  import Plug.Conn
  @behaviour Plug

  alias Escalated.Api.HostAuth
  alias Escalated.Schemas.ApiToken
  alias Escalated.Services.ApiTokenService

  # The ability the ticket API needs, as Laravel's `AuthenticateApiToken:agent`.
  @ability "agent"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case bearer_token(conn) do
      {:ok, plain} ->
        case escalated_token(plain) do
          %ApiToken{} = token -> authenticate_token(conn, token)
          nil -> conn |> identify(HostAuth.validate(plain))
        end

      :error ->
        if conn.assigns[:current_user],
          do: identify(conn, {:ok, conn.assigns.current_user}),
          else: identify(conn, :error)
    end
  end

  @doc "Whether the API accepts Escalated-issued API tokens."
  def tokens_enabled?, do: Escalated.config(:api_tokens_enabled, false) == true

  defp escalated_token(plain) do
    if tokens_enabled?(), do: ApiTokenService.find_by_plain_text(plain)
  end

  defp authenticate_token(conn, token) do
    cond do
      ApiToken.expired?(token) ->
        refuse(conn, 401, "Token has expired.")

      not ApiToken.has_ability?(token, @ability) ->
        refuse(conn, 403, "Insufficient permissions.")

      true ->
        case owner(token) do
          nil ->
            refuse(conn, 401, "Token owner not found.")

          user ->
            {:ok, _} = ApiTokenService.touch(token, remote_ip(conn))

            conn
            |> assign(:escalated_api_token, token)
            |> identify({:ok, user})
        end
    end
  end

  defp owner(%ApiToken{user_id: user_id}) do
    Escalated.user_repo().get(Escalated.user_schema(), user_id)
  rescue
    Ecto.Query.CastError -> nil
  end

  defp identify(conn, {:ok, user}) when not is_nil(user),
    do: conn |> assign(:current_user, user) |> check_membership()

  defp identify(conn, _), do: refuse(conn, 401, "Authentication required")

  defp refuse(conn, status, message) do
    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{error: message})
    |> halt()
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" -> {:ok, token}
      _ -> :error
    end
  end

  defp remote_ip(%Plug.Conn{remote_ip: ip}) when is_tuple(ip),
    do: ip |> :inet.ntoa() |> to_string()

  defp remote_ip(_conn), do: nil

  defp check_membership(conn) do
    if Escalated.Tenancy.member?(conn.assigns.current_user),
      do: Escalated.Plugs.TicketVisibility.call(conn, []),
      else: refuse(conn, 403, "Tenant access denied")
  end
end
