defmodule Escalated.SsoEnforcementTest do
  @moduledoc """
  ADR 2026-10-29-configurable-access-features, single sign-on: an
  install-level switch (`config :escalated, access: [sso: true]` or
  `ESCALATED_SSO`). Off, every SSO route and the SSO settings screen answer
  404. On, `{prefix}/sso/login` signs users in with the provider chosen in
  Admin > Settings > SSO. Every request goes through the router, carrying the
  session from one request to the next the way a browser's cookie does.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.{AccessFeatures, HostTestRepo, Sso}
  alias Escalated.Schemas.{Role, RoleUser, SsoMessageId, TwoFactor}
  alias Escalated.Services.{SettingsService, TwoFactorService}
  alias Escalated.Test.{HostUser, Router, SharedPropsRouter}

  @envs ~w(ESCALATED_SSO ESCALATED_SSO_CREATE_USERS ESCALATED_SSO_SYNC_ROLES ESCALATED_SSO_BASE_URL
           ESCALATED_SSO_JWT_AUDIENCE ESCALATED_SSO_CLOCK_SKEW ESCALATED_SSO_REDIRECT_TO
           ESCALATED_ROLES_PERMISSIONS ESCALATED_TWO_FACTOR)

  @base "https://help.example.test"
  @secret "sso-shared-secret-of-a-decent-length"

  # Stands in for the IdP's token and userinfo endpoints. Each request is
  # sent to the test process, which runs the router in-process.
  defmodule FakeIdp do
    @moduledoc false
    @behaviour Assent.HTTPAdapter

    @impl true
    def request(method, url, body, headers, _opts) do
      send(self(), {:idp_request, method, url, body, headers})

      response =
        case Process.get({__MODULE__, url}) do
          nil -> {404, %{"error" => "not_found"}}
          response -> response
        end

      {status, payload} = response

      {:ok,
       %Assent.HTTPAdapter.HTTPResponse{
         status: status,
         headers: [{"content-type", "application/json"}],
         body: Jason.encode!(payload)
       }}
    end
  end

  # A host that mounts the SSO routes in a pipeline of their own, outside its
  # sign-in requirement and CSRF check, as docs/access-control.md shows.
  defmodule SsoOnlyRouter do
    @moduledoc false
    use Phoenix.Router
    use Escalated.Router

    pipeline :escalated_sso do
      plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
      plug :fetch_session
    end

    scope "/" do
      pipe_through :escalated_sso
      escalated_sso_routes("/support")
    end
  end

  setup do
    previous = Map.new(@envs, &{&1, System.get_env(&1)})
    Enum.each(@envs, &System.delete_env/1)
    Application.put_env(:escalated, :sso, sso_config())

    on_exit(fn ->
      Enum.each(
        [:access, :sso, :two_factor_secret, :rate_limit_backend],
        &Application.delete_env(:escalated, &1)
      )

      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  # The host's sign-in: a fresh login token in the session, as
  # phx.gen.auth's UserAuth.log_in_user does.
  defp sso_config(extra \\ []) do
    [
      base_url: @base,
      http_adapter: FakeIdp,
      sign_in: fn conn, user ->
        conn
        |> Plug.Conn.put_session("user_token", "sso-#{user.id}")
        |> Plug.Conn.put_session("signed_in_user", user.id)
      end
    ] ++ extra
  end

  defp sso!(extra), do: Application.put_env(:escalated, :sso, sso_config(extra))

  defp on!(extra \\ []), do: Application.put_env(:escalated, :access, [sso: true] ++ extra)

  defp repo, do: Escalated.repo()

  defp jwt_provider!(extra \\ %{}) do
    Sso.save(
      Map.merge(
        %{
          "sso_provider" => "jwt",
          "sso_url" => "https://idp.example.test/login",
          "sso_jwt_secret" => @secret,
          "sso_jwt_algorithm" => "HS256"
        },
        extra
      )
    )
  end

  defp oauth_provider! do
    Sso.save(%{
      "sso_provider" => "oauth",
      "sso_oauth_authorize_url" => "https://idp.example.test/authorize",
      "sso_oauth_token_url" => "https://idp.example.test/token",
      "sso_oauth_userinfo_url" => "https://idp.example.test/userinfo",
      "sso_oauth_client_id" => "escalated-client",
      "sso_oauth_client_secret" => "client-secret",
      "sso_oauth_scopes" => "openid profile email"
    })
  end

  defp user!(attrs \\ %{}), do: host_user!(Map.merge(%{is_agent: true}, attrs))

  # A request through `router`; `session` carries the previous response's.
  defp req(method, path, opts \\ []) do
    body = Keyword.get(opts, :body)

    base =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    user = Keyword.get(opts, :user)

    base =
      base
      |> init_test_session(Keyword.get(opts, :session, %{}))
      |> then(&if(user, do: assign(&1, :current_user, user), else: &1))

    base =
      if Keyword.get(opts, :inertia),
        do:
          base
          |> put_req_header("x-inertia", "true")
          |> put_req_header("x-inertia-version", inertia_version()),
        else: base

    router = Keyword.get(opts, :router, Router)
    router.call(base, router.init([]))
  end

  defp session(conn), do: conn.private[:plug_session]

  defp signed_in?(conn, user),
    do: conn.status in [302, 303] and session(conn)["signed_in_user"] == user.id

  defp refused?(conn), do: conn.status == 403 and is_nil(session(conn)["signed_in_user"])

  defp token(claims, opts \\ []) do
    alg = Keyword.get(opts, :alg, "HS256")
    key = Keyword.get(opts, :key, @secret)
    signer = Joken.Signer.create(alg, key)
    {:ok, token, _} = Joken.encode_and_sign(claims, signer)
    token
  end

  defp claims(user, extra \\ %{}) do
    Map.merge(
      %{
        "email" => user.email,
        "name" => user.name,
        "aud" => @base,
        "exp" => System.os_time(:second) + 300,
        "iat" => System.os_time(:second),
        "jti" => "jti-#{System.unique_integer([:positive])}"
      },
      extra
    )
  end

  defp jwt_callback(token, opts \\ []),
    do: req(:get, "/support/sso/jwt/callback?" <> URI.encode_query(%{"jwt" => token}), opts)

  defp b64(map), do: map |> Jason.encode!() |> Base.url_encode64(padding: false)

  # --- Switch off (the default) ----------------------------------------------

  test "off: every SSO route and the settings screen answer 404, features.sso is false" do
    refute AccessFeatures.sso?()
    jwt_provider!()
    admin = user!(%{is_admin: true})

    for {method, path} <- [
          get: "/support/sso/login",
          get: "/support/sso/saml/metadata",
          post: "/support/sso/saml/acs",
          get: "/support/sso/oauth/callback",
          get: "/support/sso/jwt/callback",
          post: "/support/sso/jwt/callback"
        ] do
      assert req(method, path).status == 404, "#{method} #{path} answered while SSO is off"
    end

    # A valid token signs nobody in while the switch is off.
    assert jwt_callback(token(claims(user!()))).status == 404

    assert req(:get, "/support/admin/settings/sso", user: admin, inertia: true).status == 404

    assert req(:post, "/support/admin/settings/sso",
             user: admin,
             body: %{"sso_provider" => "none"}
           ).status == 404

    props = shared_props(admin)
    assert props["features"]["sso"] == false
  end

  test "on: features.sso is true and the settings screen renders with masked secrets and endpoints" do
    on!()
    jwt_provider!()
    admin = user!(%{is_admin: true})

    assert AccessFeatures.sso?()
    assert shared_props(admin)["features"]["sso"] == true

    props =
      req(:get, "/support/admin/settings/sso", user: admin, inertia: true)
      |> page!("Escalated/Admin/Settings/SsoSettings")

    assert props["settings"]["sso_provider"] == "jwt"
    assert props["settings"]["sso_jwt_secret"] == "********"
    assert props["settings"]["sso_oauth_client_secret"] == ""
    refute inspect(props) =~ @secret

    assert props["endpoints"] == %{
             "login" => @base <> "/support/sso/login",
             "sp_entity_id" => @base <> "/support/sso/saml/metadata",
             "metadata" => @base <> "/support/sso/saml/metadata",
             "acs" => @base <> "/support/sso/saml/acs",
             "oauth_redirect" => @base <> "/support/sso/oauth/callback",
             "jwt_callback" => @base <> "/support/sso/jwt/callback"
           }
  end

  test "on: saving settings keeps a secret posted back masked and refuses SAML" do
    on!()
    jwt_provider!()
    admin = user!(%{is_admin: true})

    conn =
      req(:post, "/support/admin/settings/sso",
        user: admin,
        body: %{
          "sso_provider" => "jwt",
          "sso_url" => "https://idp.example.test/other",
          "sso_jwt_secret" => "********",
          "sso_jwt_algorithm" => "HS384"
        }
      )

    assert conn.status in [302, 303]
    settings = Sso.settings()
    assert settings["sso_url"] == "https://idp.example.test/other"
    assert settings["sso_jwt_secret"] == @secret
    assert settings["sso_jwt_algorithm"] == "HS384"

    req(:post, "/support/admin/settings/sso",
      user: admin,
      body: %{"sso_provider" => "saml", "sso_entity_id" => "https://idp.example.test"}
    )

    assert Sso.provider() == "jwt"
    assert Sso.settings()["sso_entity_id"] == ""
  end

  test "the switch is config or env only; a stored setting of the same name changes nothing" do
    admin = user!(%{is_admin: true})

    req(:post, "/support/admin/settings", user: admin, body: %{"sso" => true})
    SettingsService.set("sso", "1", "general")

    refute AccessFeatures.sso?()
    assert req(:get, "/support/sso/login").status == 404

    System.put_env("ESCALATED_SSO", "true")
    assert AccessFeatures.sso?()

    # Config, when set, wins over the environment.
    Application.put_env(:escalated, :access, sso: false)
    refute AccessFeatures.sso?()
  end

  test "sso_provider none makes sso/login answer 404" do
    on!()
    assert Sso.provider() == "none"
    assert req(:get, "/support/sso/login").status == 404
    assert jwt_callback("anything").status == 404
  end

  test "a provider other than the chosen one answers 404" do
    on!()
    jwt_provider!()

    assert req(:get, "/support/sso/oauth/callback?code=x&state=y").status == 404
    assert req(:post, "/support/sso/saml/acs").status == 404
    assert req(:get, "/support/sso/saml/metadata").status == 404
  end

  # --- JWT ---------------------------------------------------------------------

  test "jwt: sso/login redirects to the IdP with the callback as return_to" do
    on!()
    jwt_provider!()

    conn = req(:get, "/support/sso/login")
    assert conn.status == 302

    assert location(conn) ==
             "https://idp.example.test/login?" <>
               URI.encode_query(%{"return_to" => @base <> "/support/sso/jwt/callback"})
  end

  test "jwt: a valid token signs in the matched user, by email case-insensitively" do
    on!()
    jwt_provider!()
    user = user!(%{email: "Agent.Smith@Example.test"})

    conn = jwt_callback(token(claims(user, %{"email" => "agent.smith@example.TEST"})))

    assert signed_in?(conn, user)
    assert location(conn) == "/support/agent/dashboard"
    assert session(conn)["user_token"] == "sso-#{user.id}"
  end

  test "jwt: a token can also be posted, and RS256 verifies with the configured public key" do
    on!()
    jwk = JOSE.JWK.generate_key({:rsa, 2048})
    {_, private_pem} = JOSE.JWK.to_pem(jwk)
    {_, public_pem} = jwk |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    private = %{"pem" => private_pem}
    jwt_provider!(%{"sso_jwt_algorithm" => "RS256", "sso_jwt_secret" => public_pem})
    user = user!()

    conn =
      req(:post, "/support/sso/jwt/callback",
        body: %{"jwt" => token(claims(user), alg: "RS256", key: private)}
      )

    assert signed_in?(conn, user)

    # Algorithm confusion: an HS256 token keyed with the public key itself.
    forged = token(claims(user), alg: "HS256", key: public_pem)
    assert refused?(jwt_callback(forged))
  end

  test "jwt: refused for a bad signature, alg none, a wrong algorithm and bad claims" do
    on!()
    jwt_provider!()
    user = user!()
    now = System.os_time(:second)

    refusals = %{
      "bad signature" => token(claims(user), key: "another-secret-entirely-different"),
      "alg none" => b64(%{"alg" => "none", "typ" => "JWT"}) <> "." <> b64(claims(user)) <> ".",
      "wrong algorithm" => token(claims(user), alg: "HS384"),
      "missing exp" => token(Map.delete(claims(user), "exp")),
      "past exp" => token(claims(user, %{"exp" => now - 3600})),
      "future nbf" => token(claims(user, %{"nbf" => now + 3600})),
      "wrong aud" => token(claims(user, %{"aud" => "https://elsewhere.example.test"})),
      "missing aud" => token(Map.delete(claims(user), "aud")),
      "missing jti" => token(Map.delete(claims(user), "jti")),
      "tampered" =>
        token(claims(user))
        |> String.split(".")
        |> then(fn [h, _p, s] ->
          Enum.join([h, b64(claims(user, %{"email" => "someone@else.test"})), s], ".")
        end),
      "garbage" => "not.a.jwt"
    }

    for {name, jwt} <- refusals do
      assert refused?(jwt_callback(jwt)), "#{name} was not refused"
    end
  end

  test "jwt: a jti works once" do
    on!()
    jwt_provider!()
    user = user!()
    jwt = token(claims(user, %{"jti" => "only-once"}))

    assert signed_in?(jwt_callback(jwt), user)
    assert refused?(jwt_callback(jwt))

    assert repo().aggregate(from(m in SsoMessageId, where: m.message_id == "only-once"), :count) ==
             1
  end

  test "escalated_sso_routes/1 mounts the same routes for a pipeline of their own" do
    jwt_provider!()
    user = user!()

    assert req(:get, "/support/sso/login", router: SsoOnlyRouter).status == 404

    on!()
    assert req(:get, "/support/sso/login", router: SsoOnlyRouter).status == 302

    conn =
      req(:post, "/support/sso/jwt/callback",
        router: SsoOnlyRouter,
        body: %{"jwt" => token(claims(user))}
      )

    assert signed_in?(conn, user)
  end

  test "jwt: the audience can be configured" do
    on!()
    sso!(jwt_audience: "urn:escalated:help")
    jwt_provider!()
    user = user!()

    assert refused?(jwt_callback(token(claims(user))))
    assert signed_in?(jwt_callback(token(claims(user, %{"aud" => "urn:escalated:help"}))), user)
  end

  # --- OAuth 2 / OIDC -------------------------------------------------------------

  defp idp_responds!(user_payload) do
    Process.put(
      {FakeIdp, "https://idp.example.test/token"},
      {200, %{"access_token" => "at-123", "token_type" => "Bearer", "expires_in" => 300}}
    )

    Process.put({FakeIdp, "https://idp.example.test/userinfo"}, {200, user_payload})
  end

  # sso/login, then the IdP's redirect back with `params`.
  defp oauth_round_trip(params_fun) do
    start = req(:get, "/support/sso/login")
    assert start.status == 302
    url = URI.parse(location(start))
    query = URI.decode_query(url.query)

    callback =
      req(:get, "/support/sso/oauth/callback?" <> URI.encode_query(params_fun.(query)),
        session: session(start)
      )

    {query, callback}
  end

  test "oauth: a matching state with a successful exchange and userinfo signs in the user; PKCE S256 is sent" do
    on!()
    oauth_provider!()
    user = user!()
    idp_responds!(%{"email" => user.email, "name" => user.name, "email_verified" => true})

    {query, conn} = oauth_round_trip(&%{"code" => "auth-code", "state" => &1["state"]})

    assert query["client_id"] == "escalated-client"
    assert query["redirect_uri"] == @base <> "/support/sso/oauth/callback"
    assert query["response_type"] == "code"
    assert query["scope"] == "openid profile email"
    assert query["code_challenge_method"] == "S256"

    assert signed_in?(conn, user)
    assert location(conn) == "/support/agent/dashboard"
    refute Map.has_key?(session(conn), "escalated_sso_oauth")

    assert_received {:idp_request, :post, "https://idp.example.test/token", body, _headers}
    sent = URI.decode_query(body)
    assert sent["code"] == "auth-code"
    assert sent["grant_type"] == "authorization_code"
    assert sent["client_secret"] == "client-secret"

    assert Base.url_encode64(:crypto.hash(:sha256, sent["code_verifier"]), padding: false) ==
             query["code_challenge"]

    assert_received {:idp_request, :get, "https://idp.example.test/userinfo", nil, headers}
    assert {"authorization", "Bearer at-123"} in headers
  end

  test "oauth: a missing or mismatched state, an IdP error or no session state is refused" do
    on!()
    oauth_provider!()
    user = user!()
    idp_responds!(%{"email" => user.email})

    {_, missing} = oauth_round_trip(fn _ -> %{"code" => "auth-code"} end)
    assert refused?(missing)

    {_, mismatched} = oauth_round_trip(fn _ -> %{"code" => "auth-code", "state" => "forged"} end)
    assert refused?(mismatched)

    {_, error} =
      oauth_round_trip(&%{"error" => "access_denied", "state" => &1["state"]})

    assert refused?(error)

    # A callback with no sign-in started in this session.
    assert refused?(req(:get, "/support/sso/oauth/callback?code=auth-code&state=whatever"))

    refute_received {:idp_request, :post, "https://idp.example.test/token", _, _}
  end

  test "oauth: the state is single use" do
    on!()
    oauth_provider!()
    user = user!()
    idp_responds!(%{"email" => user.email})

    start = req(:get, "/support/sso/login")
    state = URI.decode_query(URI.parse(location(start)).query)["state"]
    path = "/support/sso/oauth/callback?" <> URI.encode_query(%{"code" => "c", "state" => state})

    first = req(:get, path, session: session(start))
    assert signed_in?(first, user)

    # Replaying the callback with the session as it was before.
    assert refused?(req(:get, path, session: Map.delete(session(first), "signed_in_user")))
  end

  test "oauth: a profile saying the email is not verified is refused" do
    on!()
    oauth_provider!()
    user = user!()
    idp_responds!(%{"email" => user.email, "email_verified" => false})

    {_, conn} = oauth_round_trip(&%{"code" => "auth-code", "state" => &1["state"]})
    assert refused?(conn)
  end

  # --- SAML ----------------------------------------------------------------------

  test "saml: not available, so sign-in and every response are refused" do
    on!()
    SettingsService.set("sso_provider", "saml", "sso")
    SettingsService.set("sso_entity_id", "https://idp.example.test", "sso")
    SettingsService.set("sso_login_url", "https://idp.example.test/sso", "sso")

    assert refused?(req(:get, "/support/sso/login"))
    assert refused?(req(:get, "/support/sso/saml/metadata"))

    response =
      Base.encode64("<samlp:Response xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\"/>")

    assert refused?(req(:post, "/support/sso/saml/acs", body: %{"SAMLResponse" => response}))
  end

  # --- Users and roles -----------------------------------------------------------

  test "an unknown email is refused when create_users is off and creates a user when it is on" do
    on!()
    jwt_provider!()
    email = "new.person@example.test"

    assert refused?(jwt_callback(token(%{claims(user!()) | "email" => email})))
    assert HostTestRepo.get_by(HostUser, email: email) == nil

    sso!(create_users: true)
    conn = jwt_callback(token(%{claims(user!()) | "email" => email, "name" => "New Person"}))

    created = HostTestRepo.get_by(HostUser, email: email)
    assert created.name == "New Person"
    refute created.is_admin
    refute created.is_agent
    assert signed_in?(conn, created)
  end

  test "role mapping assigns the named role only with roles on and sync_roles on" do
    jwt_provider!()
    role = repo().insert!(Role.changeset(%Role{}, %{name: "Mapped", slug: "mapped-role"}))
    other = repo().insert!(Role.changeset(%Role{}, %{name: "Other", slug: "other-role"}))
    user = user!()
    {:ok, _} = Escalated.Roles.assign(user.id, "other-role")

    roles = fn ->
      from(ru in RoleUser, where: ru.user_id == ^user.id, select: ru.role_id)
      |> repo().all()
      |> Enum.sort()
    end

    sign_in! = fn ->
      assert signed_in?(jwt_callback(token(claims(user, %{"role" => "mapped-role"}))), user)
    end

    # Roles off, sync on.
    on!()
    sso!(sync_roles: true)
    sign_in!.()
    assert roles.() == [other.id]

    # Roles on, sync off.
    on!(roles_permissions: true)
    sso!(sync_roles: false)
    sign_in!.()
    assert roles.() == [other.id]

    # Both on: the asserted role replaces the user's roles.
    sso!(sync_roles: true)
    sign_in!.()
    assert roles.() == [role.id]

    # An unknown role changes nothing.
    assert signed_in?(jwt_callback(token(claims(user, %{"role" => "no-such-role"}))), user)
    assert roles.() == [role.id]
  end

  test "sign-in lands on redirect_to, or the host's user_return_to" do
    on!()
    jwt_provider!()
    user = user!()

    conn =
      jwt_callback(token(claims(user)), session: %{"user_return_to" => "/support/agent/tickets"})

    assert location(conn) == "/support/agent/tickets"

    conn = jwt_callback(token(claims(user)), session: %{"user_return_to" => "//evil.example"})
    assert location(conn) == "/support/agent/dashboard"

    sso!(redirect_to: "/support/admin/reports")
    assert location(jwt_callback(token(claims(user)))) == "/support/admin/reports"
  end

  test "without a host sign_in callback every sign-in is refused" do
    on!()
    Application.put_env(:escalated, :sso, base_url: @base)
    jwt_provider!()
    assert refused?(jwt_callback(token(claims(user!()))))
  end

  test "signing in through SSO does not skip the two-factor challenge" do
    on!(two_factor: true)
    Application.put_env(:escalated, :two_factor_secret, String.duplicate("two-factor-key-", 3))
    limiter = start_supervised!({Escalated.RateLimiter, name: nil})
    Process.put(__MODULE__.Limiter, limiter)
    Application.put_env(:escalated, :rate_limit_backend, __MODULE__.Limiter)

    # The host's sign-in here keeps the same login token, so only the
    # cleared two-factor mark brings the challenge back.
    sso!(sign_in: fn conn, user -> Plug.Conn.put_session(conn, "signed_in_user", user.id) end)
    jwt_provider!()
    user = user!()

    {:ok, _} = TwoFactorService.setup(user)

    from(t in TwoFactor, where: t.user_id == ^user.id)
    |> repo().update_all(set: [is_enabled: true])

    {:ok, secret} =
      Base.decode32(repo().get_by!(TwoFactor, user_id: user.id).secret, padding: false)

    login = %{"user_token" => "login-1"}

    passed =
      req(:post, "/support/two-factor/challenge",
        user: user,
        session: login,
        body: %{"code" => NimbleTOTP.verification_code(secret)}
      )

    assert passed.status in [302, 303]

    assert req(:get, "/support/agent/dashboard",
             user: user,
             session: session(passed),
             inertia: true
           ).status ==
             200

    sso = jwt_callback(token(claims(user)), session: session(passed))
    assert signed_in?(sso, user)

    challenged =
      req(:get, "/support/agent/dashboard", user: user, session: session(sso), inertia: true)

    assert challenged.status in [302, 303]
    assert location(challenged) == "/support/two-factor/challenge"
  end

  defmodule Limiter do
    @moduledoc false
    def check(bucket, key, max, window),
      do: Escalated.RateLimiter.check(bucket, key, max, window, Process.get(__MODULE__))
  end

  defp shared_props(user) do
    conn =
      req(:get, "/support/admin/departments",
        user: user,
        inertia: true,
        router: SharedPropsRouter
      )

    assert conn.status == 200, "answered #{conn.status}: #{conn.resp_body}"
    Jason.decode!(conn.resp_body)["props"]["escalated"]
  end
end
