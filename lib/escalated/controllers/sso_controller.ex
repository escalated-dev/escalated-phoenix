defmodule Escalated.Controllers.SsoController do
  @moduledoc """
  Sign-in through the SSO provider chosen in Admin > Settings > SSO (ADR
  2026-10-29-configurable-access-features). Every route answers 404 while
  `access: [sso: true]` is off (`Escalated.Plugs.EnsureFeatureEnabled.Sso`),
  and for a provider other than the chosen one.

  - `GET {prefix}/sso/login` starts sign-in; with `sso_provider = none` it
    answers 404.
  - `GET {prefix}/sso/oauth/callback`: OAuth 2 / OIDC (`Escalated.Sso.OAuth`).
  - `GET|POST {prefix}/sso/jwt/callback`: JWT hand-off (`Escalated.Sso.Jwt`).
  - `GET {prefix}/sso/saml/metadata` and `POST {prefix}/sso/saml/acs`: SAML is
    not available in this package yet (no maintained Elixir SAML library
    meets the ADR's checks on the supported Elixir and OTP versions), so with
    `sso_provider = saml` sign-in and every response are refused.

  On success the user is resolved (`Escalated.Sso.UserResolver`), the
  two-factor mark is cleared so the challenge still applies, the session is
  renewed, the host's `sso: [sign_in: ...]` callback signs the user in, and
  the browser goes to `sso: [redirect_to:]`, the host's `user_return_to`, or
  the agent dashboard. Every refusal answers 403 with a generic message and
  logs the reason.
  """
  use Phoenix.Controller, formats: [:html, :json]
  import Plug.Conn
  require Logger

  alias Escalated.Plugs.RequireTwoFactor
  alias Escalated.Sso
  alias Escalated.Sso.{Jwt, OAuth, UserResolver}
  alias Escalated.TwoFactorSession

  @oauth_session "escalated_sso_oauth"
  @saml_unavailable "SAML is not available in this package; every SAML sign-in is refused"

  def login(conn, _params) do
    case Sso.provider() do
      "none" -> not_found(conn)
      "oauth" -> start_oauth(conn)
      "jwt" -> start_jwt(conn)
      "saml" -> refuse(conn, @saml_unavailable)
    end
  end

  def saml_metadata(conn, _params) do
    with_provider(conn, "saml", fn -> refuse(conn, @saml_unavailable) end)
  end

  def saml_acs(conn, _params) do
    with_provider(conn, "saml", fn -> refuse(conn, @saml_unavailable) end)
  end

  def oauth_callback(conn, params) do
    with_provider(conn, "oauth", fn ->
      stored = get_session(conn, @oauth_session)
      conn = delete_session(conn, @oauth_session)

      result =
        if params["error"] do
          {:error, "the provider returned #{inspect(params["error"])}"}
        else
          OAuth.callback(
            Sso.settings(),
            Sso.url(conn, :oauth_callback),
            stored || %{},
            Map.take(params, ["code", "state"])
          )
        end

      sign_in(conn, result)
    end)
  end

  def jwt_callback(conn, params) do
    with_provider(conn, "jwt", fn ->
      sign_in(conn, Jwt.validate(params["jwt"], Sso.settings(), Sso.jwt_audience(conn)))
    end)
  end

  defp start_oauth(conn) do
    case OAuth.authorize(Sso.settings(), Sso.url(conn, :oauth_callback)) do
      {:ok, url, session_params} ->
        conn
        |> put_session(@oauth_session, session_params)
        |> redirect(external: url)

      {:error, reason} ->
        refuse(conn, "OAuth: " <> reason)
    end
  end

  defp start_jwt(conn) do
    settings = Sso.settings()
    url = String.trim(settings["sso_login_url"])

    if url == "" do
      refuse(conn, "JWT sign-in has no login URL configured")
    else
      separator = if String.contains?(url, "?"), do: "&", else: "?"
      query = URI.encode_query(%{"return_to" => Sso.url(conn, :jwt_callback)})
      redirect(conn, external: url <> separator <> query)
    end
  end

  defp sign_in(conn, {:error, reason}), do: refuse(conn, reason)

  defp sign_in(conn, {:ok, identity}) do
    with {:ok, user} <- UserResolver.resolve(identity),
         {:ok, callback} <- sign_in_callback() do
      target = target(conn)

      conn =
        conn
        |> TwoFactorSession.forget()
        |> configure_session(renew: true)
        |> call(callback, user)

      Logger.info(
        "Escalated SSO: signed in user #{inspect(Map.get(user, :id))} via #{Sso.provider()}"
      )

      if conn.halted or conn.state != :unset, do: conn, else: redirect(conn, to: target)
    else
      {:error, reason} -> refuse(conn, reason)
    end
  end

  defp sign_in_callback do
    case Sso.sign_in_callback() do
      nil -> {:error, "no sso: [sign_in: ...] callback is configured"}
      callback -> {:ok, callback}
    end
  end

  defp call(conn, {module, function}, user), do: apply(module, function, [conn, user])
  defp call(conn, fun, user) when is_function(fun, 2), do: fun.(conn, user)

  defp target(conn) do
    configured = Sso.option(:redirect_to)
    return_to = get_session(conn, :user_return_to)

    cond do
      is_binary(configured) and configured != "" -> configured
      local_path?(return_to) -> return_to
      true -> RequireTwoFactor.home_path()
    end
  end

  defp local_path?(path) do
    is_binary(path) and String.starts_with?(path, "/") and
      not String.starts_with?(path, "//") and not String.contains?(path, "\\")
  end

  defp with_provider(conn, provider, fun) do
    if Sso.provider() == provider, do: fun.(), else: not_found(conn)
  end

  defp refuse(conn, reason) do
    Logger.warning("Escalated SSO refused: #{reason}")

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(403, "Single sign-on failed. Contact your administrator.")
    |> halt()
  end

  defp not_found(conn) do
    conn
    |> put_status(404)
    |> json(%{error: "Not found"})
    |> halt()
  end
end
