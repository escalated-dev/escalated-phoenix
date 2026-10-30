defmodule Escalated.Controllers.Admin.SsoSettingsController do
  @moduledoc """
  The SSO provider and its fields (`Escalated/Admin/Settings/SsoSettings`),
  as escalated-laravel's `escalated.admin.settings.sso*`. Mounted only while
  `access: [sso: true]` is on.

  `index` renders `settings` (the `sso_*` keys, with the JWT secret and the
  OAuth client secret masked as `********`) and read-only `endpoints` for the
  admin to give the identity provider. `update` validates and saves; a
  posted mask keeps the stored secret.

  SAML cannot be chosen: this package does not support it yet, and a screen
  that saved a provider nobody enforces would claim it works.
  """
  use Phoenix.Controller, formats: [:html, :json]

  alias Escalated.Controllers.FormResponse
  alias Escalated.Rendering.UIRenderer
  alias Escalated.Sso
  alias Escalated.Sso.Jwt

  @mask "********"
  @secrets ~w(sso_jwt_secret sso_oauth_client_secret)
  @urls ~w(sso_url sso_login_url sso_logout_url sso_metadata_url sso_oauth_authorize_url sso_oauth_token_url sso_oauth_userinfo_url)

  def index(conn, _params) do
    settings =
      Enum.reduce(@secrets, Sso.settings(), fn key, acc ->
        Map.update!(acc, key, &if(&1 in [nil, ""], do: "", else: @mask))
      end)

    UIRenderer.render_page(conn, "Escalated/Admin/Settings/SsoSettings", %{
      settings: settings,
      endpoints: Sso.endpoints(conn)
    })
  end

  def update(conn, params) do
    attrs =
      params
      |> Map.take(Sso.setting_keys())
      |> Map.new(fn {key, value} -> {key, normalize(value)} end)
      |> Map.reject(fn {key, value} -> key in @secrets and masked?(value) end)

    case validate(attrs) do
      [] ->
        Sso.save(attrs)

        conn
        |> put_flash(:info, "SSO settings updated.")
        |> redirect(to: settings_path())

      errors ->
        FormResponse.invalid(conn, Map.new(errors), settings_path())
    end
  end

  defp validate(attrs) do
    provider = attrs["sso_provider"]

    []
    |> check(provider in ~w(none oauth jwt), "sso_provider", provider_message(provider))
    |> check(
      attrs["sso_jwt_algorithm"] in [nil, "" | Jwt.algorithms()],
      "sso_jwt_algorithm",
      "Choose a supported algorithm."
    )
    |> check_urls(attrs)
    |> check_lengths(attrs)
    |> require_for(provider, attrs)
    |> Enum.reverse()
  end

  defp provider_message("saml"),
    do: "SAML sign-in is not available in this package yet. Choose OAuth or JWT."

  defp provider_message(_), do: "Choose none, OAuth or JWT."

  defp require_for(errors, "jwt", attrs) do
    errors
    |> required(attrs, "sso_url", "The identity provider sign-in URL is required for JWT.")
    |> required_secret(attrs, "sso_jwt_secret", "A JWT secret or public key is required.")
  end

  defp require_for(errors, "oauth", attrs) do
    Enum.reduce(
      ~w(sso_oauth_authorize_url sso_oauth_token_url sso_oauth_userinfo_url sso_oauth_client_id),
      errors,
      &required(&2, attrs, &1, "This field is required for OAuth.")
    )
  end

  defp require_for(errors, _provider, _attrs), do: errors

  defp required(errors, attrs, key, message) do
    check(errors, present?(attrs[key]), key, message)
  end

  # A secret left out (or posted back masked) is kept, so it counts as set
  # when one is stored.
  defp required_secret(errors, attrs, key, message) do
    set? =
      present?(attrs[key]) or (not Map.has_key?(attrs, key) and present?(Sso.settings()[key]))

    check(errors, set?, key, message)
  end

  defp check_urls(errors, attrs) do
    Enum.reduce(@urls, errors, fn key, acc ->
      value = attrs[key]
      check(acc, value in [nil, ""] or url?(value), key, "Enter a valid http(s) URL.")
    end)
  end

  defp check_lengths(errors, attrs) do
    Enum.reduce(attrs, errors, fn {key, value}, acc ->
      max = if key == "sso_certificate", do: 10_000, else: 500
      check(acc, String.length(value) <= max, key, "This value is too long.")
    end)
  end

  defp check(errors, true, _key, _message), do: errors

  defp check(errors, false, key, message) do
    if List.keymember?(errors, key, 0), do: errors, else: [{key, message} | errors]
  end

  defp url?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp masked?(value), do: is_binary(value) and Regex.match?(~r/^\*{3,}$/, value)

  defp normalize(value) when is_binary(value), do: String.trim(value)
  defp normalize(_value), do: ""

  defp settings_path,
    do:
      "/" <>
        String.trim(Escalated.config(:route_prefix, "/support"), "/") <> "/admin/settings/sso"
end
