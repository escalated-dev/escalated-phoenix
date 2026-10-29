defmodule Escalated.Sso.OAuth do
  @moduledoc """
  The OAuth 2 / OIDC provider (ADR 2026-10-29-configurable-access-features):
  the authorization-code flow through `assent`, with a single-use `state`
  bound to the session and PKCE (`S256`). The code is exchanged at
  `sso_oauth_token_url` server to server and the profile read from
  `sso_oauth_userinfo_url` with the access token. A profile saying
  `email_verified: false` is refused.

  Requests go through `Escalated.Sso.HttpAdapter` (`:httpc` with peer and
  host-name verification) unless the host names another `Assent.HTTPAdapter`:

      config :escalated, sso: [http_adapter: Assent.HTTPAdapter.Req]
  """
  alias Assent.Strategy.OAuth2
  alias Escalated.Sso.Identity

  @doc """
  The IdP authorization URL and the session params (`state`, PKCE
  `code_verifier`) to keep in the session until the callback.
  """
  def authorize(settings, redirect_uri) do
    case OAuth2.authorize_url(config(settings, redirect_uri)) do
      {:ok, %{url: url, session_params: params}} ->
        {:ok, url, Map.new(params, fn {key, value} -> {to_string(key), value} end)}

      {:error, error} ->
        {:error, "could not build the authorization URL: #{Exception.message(error)}"}
    end
  rescue
    error -> {:error, "could not build the authorization URL: #{Exception.message(error)}"}
  end

  @doc """
  Checks `state` against the session's, exchanges the code with the PKCE
  verifier and reads the userinfo endpoint. `{:ok, identity}` or
  `{:error, reason}`.
  """
  def callback(settings, redirect_uri, session_params, params) do
    with {:ok, session_params} <- session_params(session_params),
         {:ok, %{user: profile}} <-
           settings
           |> config(redirect_uri)
           |> Keyword.put(:session_params, session_params)
           |> OAuth2.callback(params) do
      identity(profile, settings)
    else
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, error} -> {:error, describe(error)}
      _ -> {:error, "unexpected response from the provider"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp identity(profile, settings) when is_map(profile) do
    if profile["email_verified"] in [false, "false", 0, "0"] do
      {:error, "the provider says the email is not verified"}
    else
      Identity.build(
        claim(profile, settings["sso_attr_email"], "email"),
        claim(profile, settings["sso_attr_name"], "name"),
        claim(profile, settings["sso_attr_role"], nil)
      )
    end
  end

  defp identity(_profile, _settings), do: {:error, "the userinfo response is not an object"}

  # The session keeps string keys; assent wants its atom keys back.
  defp session_params(%{"state" => state, "code_verifier" => verifier} = params)
       when is_binary(state) and state != "" and is_binary(verifier) and verifier != "" do
    {:ok,
     %{
       state: state,
       code_verifier: verifier,
       code_challenge: params["code_challenge"],
       code_challenge_method: params["code_challenge_method"]
     }}
  end

  defp session_params(_params), do: {:error, "no state or PKCE verifier in the session"}

  defp config(settings, redirect_uri) do
    secret = settings["sso_oauth_client_secret"] || ""
    authorize_url = settings["sso_oauth_authorize_url"] || ""

    scopes =
      (settings["sso_oauth_scopes"] || "")
      |> String.split(~r/[\s,]+/, trim: true)
      |> Enum.join(" ")

    [
      client_id: settings["sso_oauth_client_id"] || "",
      client_secret: secret,
      auth_method: if(secret == "", do: nil, else: :client_secret_post),
      base_url: base(authorize_url),
      authorize_url: authorize_url,
      token_url: settings["sso_oauth_token_url"] || "",
      user_url: settings["sso_oauth_userinfo_url"] || "",
      redirect_uri: redirect_uri,
      authorization_params: if(scopes == "", do: [], else: [scope: scopes]),
      state: true,
      code_verifier: true,
      http_adapter: http_adapter()
    ]
  end

  defp http_adapter do
    case Escalated.config(:sso, []) do
      opts when is_list(opts) -> Keyword.get(opts, :http_adapter)
      opts when is_map(opts) -> Map.get(opts, :http_adapter)
      _ -> nil
    end || Escalated.Sso.HttpAdapter
  end

  defp base(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        URI.to_string(%URI{scheme: scheme, host: host, port: uri.port})

      _ ->
        url
    end
  end

  defp claim(profile, name, fallback) do
    value =
      case is_binary(name) && String.trim(name) do
        name when is_binary(name) and name != "" -> get_in(profile, String.split(name, "."))
        _ -> nil
      end

    value = if is_nil(value) and fallback, do: profile[fallback], else: value
    if is_binary(value), do: String.trim(value), else: ""
  rescue
    _ -> ""
  end

  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(error), do: inspect(error)
end
