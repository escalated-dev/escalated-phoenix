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
  def authenticate(params), do: call(:api_authenticator, [params])

  @doc "Register a new account via the host."
  @spec register(map()) :: result
  def register(params), do: call(:api_registrar, [params])

  @doc "Exchange/refresh a token via the host."
  @spec refresh(String.t()) :: result
  def refresh(token), do: call(:api_token_refresher, [token])

  @doc "Validate a token and return the associated user via the host."
  @spec validate(String.t()) :: result
  def validate(token), do: call(:api_token_validator, [token])

  @doc "Update the authenticated user's profile via the host."
  @spec update_profile(String.t(), map()) :: result
  def update_profile(token, attrs), do: call(:api_profile_updater, [token, attrs])

  @doc """
  Invalidate a token via the host (best-effort). Always returns `:ok` — a
  logout endpoint should succeed even when the host does not track tokens.
  """
  @spec logout(String.t() | nil) :: :ok
  def logout(token) do
    case Escalated.config(:api_logout) do
      callback when is_function(callback, 1) ->
        _ = callback.(token)
        :ok

      _ ->
        :ok
    end
  end

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
