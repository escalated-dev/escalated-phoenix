defmodule Escalated.Api.HostAuth do
  @moduledoc """
  Resolves and invokes host-app-provided authentication callbacks for the
  general JSON API (`/api/v1/auth/*`).

  Escalated does not own user credentials or sessions, so it ships no
  password-hashing or session dependency. Instead the host application
  configures callbacks that validate credentials and issue/validate tokens:

      config :escalated,
        api_authenticator: &MyApp.api_login/1,
        api_registrar: &MyApp.api_register/1,
        api_token_validator: &MyApp.api_validate_token/1,
        api_token_refresher: &MyApp.api_refresh_token/1,
        api_profile_updater: &MyApp.api_update_profile/2,
        api_logout: &MyApp.api_logout/1

  Each callback returns `{:ok, map}` on success, `{:error, reason}` for a
  client error (422), or `:error` / `:unauthorized` for an auth failure (401).
  When a callback is not configured the API responds `501 Not Implemented`.
  """

  @type result :: {:ok, map()} | {:error, String.t()} | :unauthorized | :not_configured

  @doc "Authenticate a login request (email/password etc.) via the host."
  @spec authenticate(map()) :: result
  def authenticate(params), do: call(:api_authenticator, [params]) |> member_response()

  @doc "Register a new account via the host."
  @spec register(map()) :: result
  def register(params) do
    if Escalated.Tenancy.enabled?(),
      do:
        call(:api_tenant_registrar, [params, Escalated.Tenancy.current_id!()])
        |> member_response(),
      else: call(:api_registrar, [params])
  end

  @doc "Exchange/refresh a token via the host."
  @spec refresh(String.t()) :: result
  def refresh(token) do
    with :ok <- authorize_token(token),
         do: call(:api_token_refresher, [token]) |> member_response()
  end

  @doc "Validate a token and return the associated user via the host."
  @spec validate(String.t()) :: result
  def validate(token), do: call(:api_token_validator, [token]) |> member_response()

  @doc "Update the authenticated user's profile via the host."
  @spec update_profile(String.t(), map()) :: result
  def update_profile(token, attrs) do
    with :ok <- authorize_token(token),
         do: call(:api_profile_updater, [token, attrs]) |> member_response()
  end

  @doc """
  Invalidate a token via the host (best-effort). Always returns `:ok` — a
  logout endpoint should succeed even when the host does not track tokens.
  """
  @spec logout(String.t() | nil) :: :ok
  def logout(token) do
    if authorize_token(token) == :ok, do: logout_authorized(token), else: :ok
  end

  defp logout_authorized(token) do
    case Escalated.config(:api_logout) do
      callback when is_function(callback, 1) ->
        _ = callback.(token)
        :ok

      _ ->
        :ok
    end
  end

  defp authorize_token(token) do
    if Escalated.Tenancy.enabled?() do
      case validate(token) do
        {:ok, _} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  defp member_response({:ok, data} = result) do
    user = Map.get(data, :user, Map.get(data, "user", data))
    if Escalated.Tenancy.member?(user), do: result, else: :unauthorized
  end

  defp member_response(result), do: result

  defp call(key, args) do
    arity = length(args)

    case Escalated.config(key) do
      callback when is_function(callback, arity) ->
        normalize(apply(callback, args))

      _ ->
        :not_configured
    end
  end

  defp normalize({:ok, data}) when is_map(data), do: {:ok, data}
  defp normalize({:error, reason}), do: {:error, to_string(reason)}
  defp normalize(:error), do: :unauthorized
  defp normalize(:unauthorized), do: :unauthorized
  defp normalize(_other), do: {:error, "Unexpected response from host auth callback"}
end
