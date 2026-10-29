defmodule Escalated.Sso do
  @moduledoc """
  Single sign-on (ADR 2026-10-29-configurable-access-features in
  escalated-developer-context).

  Two layers of configuration:

  - **The provider and its fields** are runtime settings an admin edits in
    Admin > Settings > SSO (`sso_provider`: `none`, `oauth`, `jwt` or `saml`,
    plus the `sso_*` keys in `settings/0`). They only take effect while the
    install-level switch (`config :escalated, access: [sso: true]` or
    `ESCALATED_SSO`) is on.
  - **The rules around it** are install-level and read from config, then the
    environment:

        config :escalated,
          sso: [
            # Signs the resolved host user in and returns the conn (required).
            sign_in: {MyAppWeb.UserAuth, :escalated_sso_sign_in},
            base_url: "https://help.example.com",   # ESCALATED_SSO_BASE_URL
            jwt_audience: "https://help.example.com", # ESCALATED_SSO_JWT_AUDIENCE
            clock_skew: 120,                        # ESCALATED_SSO_CLOCK_SKEW (max 300)
            create_users: false,                    # ESCALATED_SSO_CREATE_USERS
            sync_roles: false,                      # ESCALATED_SSO_SYNC_ROLES
            redirect_to: nil,                       # ESCALATED_SSO_REDIRECT_TO
            sp_entity_id: nil                       # ESCALATED_SSO_SP_ENTITY_ID
          ]

  See `docs/access-control.md`.
  """
  alias Escalated.Services.SettingsService

  @providers ~w(saml oauth jwt)

  # The runtime settings and their defaults, as escalated-laravel's
  # SsoService.
  @settings [
    {"sso_provider", "none"},
    {"sso_entity_id", ""},
    {"sso_url", ""},
    {"sso_login_url", ""},
    {"sso_logout_url", ""},
    {"sso_metadata_url", ""},
    {"sso_certificate", ""},
    {"sso_attr_email", "email"},
    {"sso_attr_name", "name"},
    {"sso_attr_role", "role"},
    {"sso_jwt_secret", ""},
    {"sso_jwt_algorithm", "HS256"},
    {"sso_oauth_authorize_url", ""},
    {"sso_oauth_token_url", ""},
    {"sso_oauth_userinfo_url", ""},
    {"sso_oauth_client_id", ""},
    {"sso_oauth_client_secret", ""},
    {"sso_oauth_scopes", "openid profile email"}
  ]

  @group "sso"

  # Install-level options: {key, env var, default}.
  @options [
    {:base_url, "ESCALATED_SSO_BASE_URL", nil},
    {:jwt_audience, "ESCALATED_SSO_JWT_AUDIENCE", nil},
    {:clock_skew, "ESCALATED_SSO_CLOCK_SKEW", 120},
    {:create_users, "ESCALATED_SSO_CREATE_USERS", false},
    {:sync_roles, "ESCALATED_SSO_SYNC_ROLES", false},
    {:redirect_to, "ESCALATED_SSO_REDIRECT_TO", nil},
    {:sp_entity_id, "ESCALATED_SSO_SP_ENTITY_ID", nil}
  ]

  @doc "The runtime setting keys an admin may save."
  def setting_keys, do: Enum.map(@settings, &elem(&1, 0))

  @doc """
  The stored SSO settings with their defaults. The legacy `sso_url` fills in
  the login URL (and, for OAuth, the authorize URL) when those are blank.
  """
  def settings do
    config = Map.new(@settings, fn {key, default} -> {key, stored(key, default)} end)
    legacy = String.trim(config["sso_url"])

    if legacy == "" do
      config
    else
      config
      |> fill("sso_login_url", legacy)
      |> then(fn c ->
        if c["sso_provider"] == "oauth", do: fill(c, "sso_oauth_authorize_url", legacy), else: c
      end)
    end
  end

  @doc "Saves the known `sso_*` keys in `attrs`; anything else is ignored."
  def save(attrs) when is_map(attrs) do
    Enum.each(setting_keys(), fn key ->
      case Map.fetch(attrs, key) do
        {:ok, value} -> SettingsService.set(key, to_string(value || ""), @group)
        :error -> :ok
      end
    end)
  end

  @doc "The chosen provider: `saml`, `oauth`, `jwt` or `none`."
  def provider do
    provider = stored("sso_provider", "none")
    if provider in @providers, do: provider, else: "none"
  end

  @doc "An install-level option (see the module doc)."
  def option(key) do
    {^key, env, default} = List.keyfind(@options, key, 0)
    config = Escalated.config(:sso, [])

    value =
      case fetch(config, key) do
        {:ok, value} -> value
        :error -> System.get_env(env)
      end

    cast(value, default)
  end

  @doc "The host's sign-in callback, `{module, function}` or a 2-arity function."
  def sign_in_callback, do: config_value(:sign_in)

  @doc "A host callback creating a user from `%{email, name}`, if configured."
  def create_user_callback, do: config_value(:create_user)

  @doc "Seconds of clock skew allowed on token windows, 0 to 300."
  def clock_skew do
    case option(:clock_skew) do
      value when is_integer(value) -> value |> max(0) |> min(300)
      _ -> 120
    end
  end

  @doc """
  The absolute base URL the SSO endpoints are published under:
  `sso: [base_url:]`, then the host endpoint's URL, then the request's.
  """
  def base_url(conn) do
    configured = option(:base_url)

    cond do
      is_binary(configured) and configured != "" ->
        String.trim_trailing(configured, "/")

      endpoint = conn.private[:phoenix_endpoint] ->
        endpoint.url()

      true ->
        %URI{scheme: to_string(conn.scheme), host: conn.host, port: conn.port}
        |> URI.to_string()
    end
  end

  @doc "`{prefix}/sso/...` for one of the SSO routes."
  def path(:login), do: prefix() <> "/sso/login"
  def path(:metadata), do: prefix() <> "/sso/saml/metadata"
  def path(:acs), do: prefix() <> "/sso/saml/acs"
  def path(:oauth_callback), do: prefix() <> "/sso/oauth/callback"
  def path(:jwt_callback), do: prefix() <> "/sso/jwt/callback"

  @doc "The absolute URL of an SSO route."
  def url(conn, name), do: base_url(conn) <> path(name)

  @doc "The SP entity ID: `sso: [sp_entity_id:]`, or the metadata URL."
  def sp_entity_id(conn) do
    case option(:sp_entity_id) do
      value when is_binary(value) and value != "" -> value
      _ -> url(conn, :metadata)
    end
  end

  @doc "The `aud` a JWT must carry: `sso: [jwt_audience:]`, or the base URL."
  def jwt_audience(conn) do
    case option(:jwt_audience) do
      value when is_binary(value) and value != "" -> value
      _ -> base_url(conn)
    end
  end

  @doc "The URLs an admin gives the identity provider (the settings page's `endpoints`)."
  def endpoints(conn) do
    %{
      login: url(conn, :login),
      sp_entity_id: sp_entity_id(conn),
      metadata: url(conn, :metadata),
      acs: url(conn, :acs),
      oauth_redirect: url(conn, :oauth_callback),
      jwt_callback: url(conn, :jwt_callback)
    }
  end

  defp prefix, do: "/" <> String.trim(Escalated.config(:route_prefix, "/support"), "/")

  defp stored(key, default) do
    case SettingsService.get(key) do
      nil -> default
      value -> value
    end
  end

  defp fill(config, key, value) do
    if config[key] == "", do: Map.put(config, key, value), else: config
  end

  defp config_value(key) do
    case fetch(Escalated.config(:sso, []), key) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp fetch(config, key) when is_list(config), do: Keyword.fetch(config, key)
  defp fetch(config, key) when is_map(config), do: Map.fetch(config, key)
  defp fetch(_config, _key), do: :error

  defp cast(nil, default), do: default
  defp cast(value, default) when is_boolean(default), do: truthy?(value)

  defp cast(value, default) when is_integer(default) do
    case value do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {int, ""} -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  defp cast(value, _default), do: value

  defp truthy?(value), do: value in [true, 1, "1", "true", "TRUE", "True", "on", "yes"]
end
