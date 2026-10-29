defmodule Escalated.TwoFactorEnforcementTest do
  @moduledoc """
  ADR 2026-10-29-configurable-access-features, two-factor: an install-level
  switch (`config :escalated, access: [two_factor: true]` or
  `ESCALATED_TWO_FACTOR`). Off, nothing is challenged and the enrolment and
  challenge routes answer 404. On, staff with a confirmed enrolment pass
  `Auth/TwoFactorChallenge` once per sign-in before any admin or agent route.
  Every request goes through the router, carrying the session from one
  request to the next the way a browser's cookie does.
  """
  use Escalated.PageCase

  import Ecto.Query, only: [from: 2]

  alias Escalated.AccessFeatures
  alias Escalated.Schemas.TwoFactor
  alias Escalated.Services.{ApiTokenService, GeneralSettings, TwoFactorService}
  alias Escalated.Test.{Router, SharedPropsRouter}

  @envs ~w(ESCALATED_TWO_FACTOR ESCALATED_TWO_FACTOR_REQUIRED)

  # The real limiter, but a fresh one per test: host user IDs are reused
  # after each test's rollback, and the limiter keys on the user ID.
  defmodule Limiter do
    @moduledoc false
    def check(bucket, key, max, window),
      do: Escalated.RateLimiter.check(bucket, key, max, window, Process.get(__MODULE__))
  end

  setup do
    previous = Map.new(@envs, &{&1, System.get_env(&1)})
    Enum.each(@envs, &System.delete_env/1)
    Application.put_env(:escalated, :two_factor_secret, String.duplicate("two-factor-key-", 3))
    limiter = start_supervised!({Escalated.RateLimiter, name: nil})
    Process.put(Limiter, limiter)
    Application.put_env(:escalated, :rate_limit_backend, Limiter)

    on_exit(fn ->
      Enum.each(
        [:access, :two_factor, :two_factor_secret, :api_tokens_enabled, :rate_limit_backend],
        &Application.delete_env(:escalated, &1)
      )

      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  defp repo, do: Escalated.repo()

  defp on!(extra \\ []), do: Application.put_env(:escalated, :access, [two_factor: true] ++ extra)

  defp staff!(kind),
    do: host_user!(%{name: "#{kind}", is_agent: true, is_admin: kind == :admin})

  # A confirmed enrolment whose secret has accepted no code yet.
  defp enrol!(user) do
    {:ok, %{recovery_codes: codes}} = TwoFactorService.setup(user)

    from(t in TwoFactor, where: t.user_id == ^user.id)
    |> repo().update_all(set: [is_enabled: true])

    two_factor = repo().get_by!(TwoFactor, user_id: user.id)
    {:ok, secret} = Base.decode32(two_factor.secret, padding: false)
    %{secret: secret, recovery_codes: codes}
  end

  defp totp(secret, steps \\ 0),
    do: NimbleTOTP.verification_code(secret, time: System.os_time(:second) + steps * 30)

  # A request through `router` with `session` (the previous response's, to
  # follow a browser). Inertia unless `json: true`.
  defp req(method, path, user, opts \\ []) do
    body = Keyword.get(opts, :body)

    base =
      if body,
        do:
          conn(method, path, Jason.encode!(body))
          |> put_req_header("content-type", "application/json"),
        else: conn(method, path)

    base =
      base
      |> init_test_session(Keyword.get(opts, :session, %{"user_token" => "login-1"}))
      |> then(&if(user, do: assign(&1, :current_user, user), else: &1))

    base =
      if Keyword.get(opts, :json),
        do: put_req_header(base, "accept", "application/json"),
        else:
          base
          |> put_req_header("x-inertia", "true")
          |> put_req_header("x-inertia-version", inertia_version())

    router = Keyword.get(opts, :router, Router)
    router.call(base, router.init([]))
  end

  defp session(conn), do: conn.private[:plug_session]

  defp redirected_to?(conn, path), do: conn.status in [302, 303] and location(conn) == path

  # Passes the challenge with a fresh code and returns the session.
  defp pass!(user, secret, session \\ %{"user_token" => "login-1"}) do
    conn =
      req(:post, "/support/two-factor/challenge", user,
        body: %{"code" => totp(secret)},
        session: session
      )

    assert conn.status in [302, 303], "verify answered #{conn.status}: #{conn.resp_body}"
    session(conn)
  end

  # --- Switch off (the default) ----------------------------------------------

  test "off: an enrolled user is not challenged and the routes answer 404" do
    refute AccessFeatures.two_factor?()
    admin = staff!(:admin)
    enrol!(admin)

    assert req(:get, "/support/admin/departments", admin).status == 200
    assert req(:get, "/support/agent/dashboard", admin).status == 200

    assert req(:get, "/support/admin/settings/two-factor", admin).status == 404
    assert req(:post, "/support/admin/settings/two-factor/setup", admin).status == 404

    assert req(:post, "/support/admin/settings/two-factor/confirm", admin, body: %{"code" => "1"}).status ==
             404

    assert req(:post, "/support/admin/settings/two-factor/disable", admin).status == 404
    assert req(:get, "/support/two-factor/challenge", admin).status == 404

    assert req(:post, "/support/two-factor/challenge", admin, body: %{"code" => "123456"}).status ==
             404

    # Enrolments are kept for when the switch is turned on.
    assert TwoFactorService.confirmed_for(admin)

    props =
      Jason.decode!(
        req(:get, "/support/admin/departments", admin, router: SharedPropsRouter).resp_body
      )

    assert props["props"]["escalated"]["features"]["two_factor"] == false
    assert props["props"]["escalated"]["two_factor_required"] == false
  end

  test "the switch is config or env only; posting a setting of that name changes nothing" do
    admin = staff!(:admin)
    req(:post, "/support/admin/settings", admin, body: %{"two_factor" => true})
    refute AccessFeatures.two_factor?()

    System.put_env("ESCALATED_TWO_FACTOR", "true")
    assert AccessFeatures.two_factor?()
    assert req(:get, "/support/admin/settings/two-factor", admin).status == 200

    Application.put_env(:escalated, :access, two_factor: false)
    refute AccessFeatures.two_factor?()
  end

  test "on: the routes work and features.two_factor is true" do
    on!()
    agent = staff!(:agent)

    props =
      page!(
        req(:get, "/support/admin/settings/two-factor", agent),
        "Escalated/Admin/Settings/TwoFactor"
      )

    assert props["enabled"] == false
    assert props["pending"] == false
    assert props["required"] == false

    shared =
      Jason.decode!(
        req(:get, "/support/agent/dashboard", agent, router: SharedPropsRouter).resp_body
      )

    assert shared["props"]["escalated"]["features"]["two_factor"] == true
  end

  # --- The challenge -----------------------------------------------------------

  test "an enrolled admin is sent from admin and agent pages to the challenge" do
    on!()
    admin = staff!(:admin)
    enrol!(admin)

    assert redirected_to?(
             req(:get, "/support/admin/departments", admin),
             "/support/two-factor/challenge"
           )

    assert redirected_to?(
             req(:get, "/support/agent/dashboard", admin),
             "/support/two-factor/challenge"
           )

    assert redirected_to?(
             req(:get, "/support/admin/settings/two-factor", admin),
             "/support/two-factor/challenge"
           )

    props =
      page!(
        req(:get, "/support/two-factor/challenge", admin),
        "Escalated/Auth/TwoFactorChallenge"
      )

    assert props["action"] == "http://www.example.com/support/two-factor/challenge"
    assert props["error"] == ""
  end

  test "an enrolled agent is challenged too, and JSON requests get 403" do
    on!()
    agent = staff!(:agent)
    enrol!(agent)

    assert redirected_to?(
             req(:get, "/support/agent/tickets", agent),
             "/support/two-factor/challenge"
           )

    conn = req(:get, "/support/agent/tickets", agent, json: true)
    assert conn.status == 403
    assert Jason.decode!(conn.resp_body)["two_factor_required"] == true
  end

  test "a valid code passes and returns to the page asked for" do
    on!()
    admin = staff!(:admin)
    %{secret: secret} = enrol!(admin)

    asked = req(:get, "/support/admin/departments?page=2", admin)
    assert redirected_to?(asked, "/support/two-factor/challenge")

    conn =
      req(:post, "/support/two-factor/challenge", admin,
        body: %{"code" => totp(secret)},
        session: session(asked)
      )

    assert redirected_to?(conn, "/support/admin/departments?page=2")
    assert req(:get, "/support/admin/departments", admin, session: session(conn)).status == 200
    assert req(:get, "/support/agent/dashboard", admin, session: session(conn)).status == 200

    # Passed, the challenge page sends them on.
    assert req(:get, "/support/two-factor/challenge", admin, session: session(conn)).status in [
             302,
             303
           ]
  end

  test "an invalid code returns a code error" do
    on!()
    admin = staff!(:admin)
    %{secret: secret} = enrol!(admin)
    wrong = if totp(secret) == "000000", do: "111111", else: "000000"

    conn = req(:post, "/support/two-factor/challenge", admin, body: %{"code" => wrong})
    assert conn.status in [302, 303]
    assert get_session(conn, "inertia_errors")["code"] =~ "not valid"
    refute get_session(conn, "escalated_two_factor_passed")

    json =
      req(:post, "/support/two-factor/challenge", admin, body: %{"code" => wrong}, json: true)

    assert json.status == 422
    assert Jason.decode!(json.resp_body)["errors"]["code"]

    assert redirected_to?(
             req(:get, "/support/admin/departments", admin, session: session(conn)),
             "/support/two-factor/challenge"
           )
  end

  test "a code cannot be used twice, nor one from an earlier step" do
    on!()
    admin = staff!(:admin)
    %{secret: secret} = enrol!(admin)
    code = totp(secret)

    first = req(:post, "/support/two-factor/challenge", admin, body: %{"code" => code})
    assert first.status in [302, 303]
    assert get_session(first, "escalated_two_factor_passed")

    # Another sign-in, replaying the same code inside its window.
    again =
      req(:post, "/support/two-factor/challenge", admin,
        body: %{"code" => code},
        session: %{"user_token" => "login-2"}
      )

    assert get_session(again, "inertia_errors")["code"]
    refute get_session(again, "escalated_two_factor_passed")

    older =
      req(:post, "/support/two-factor/challenge", admin,
        body: %{"code" => totp(secret, -1)},
        session: %{"user_token" => "login-3"}
      )

    assert get_session(older, "inertia_errors")["code"]
  end

  test "a recovery code passes once and is refused the second time" do
    on!()
    admin = staff!(:admin)
    %{recovery_codes: [recovery | _]} = enrol!(admin)

    conn =
      req(:post, "/support/two-factor/challenge", admin, body: %{"recovery_code" => recovery})

    assert redirected_to?(conn, "/support/agent/dashboard")
    assert req(:get, "/support/admin/departments", admin, session: session(conn)).status == 200

    again =
      req(:post, "/support/two-factor/challenge", admin,
        body: %{"recovery_code" => recovery},
        session: %{"user_token" => "login-2"}
      )

    assert get_session(again, "inertia_errors")["recovery_code"] =~ "not valid"
    assert length(TwoFactorService.confirmed_for(admin).recovery_codes) == 7
  end

  test "the verify route is throttled" do
    on!()
    admin = staff!(:admin)
    %{secret: secret} = enrol!(admin)
    wrong = if totp(secret) == "000000", do: "111111", else: "000000"

    for _ <- 1..5 do
      conn = req(:post, "/support/two-factor/challenge", admin, body: %{"code" => wrong})
      assert conn.status in [302, 303]
    end

    throttled =
      req(:post, "/support/two-factor/challenge", admin, body: %{"code" => totp(secret)})

    assert throttled.status == 429
    refute get_session(throttled, "escalated_two_factor_passed")
  end

  test "a new login is challenged again" do
    on!()
    admin = staff!(:admin)
    %{secret: secret} = enrol!(admin)

    passed = pass!(admin, secret)
    assert req(:get, "/support/admin/departments", admin, session: passed).status == 200

    # The host signs in again (a new login token in the same session) ...
    relogin = Map.put(passed, "user_token", "login-2")

    assert redirected_to?(
             req(:get, "/support/admin/departments", admin, session: relogin),
             "/support/two-factor/challenge"
           )

    # ... or starts a fresh session.
    assert redirected_to?(
             req(:get, "/support/admin/departments", admin, session: %{}),
             "/support/two-factor/challenge"
           )

    # A mark for one user does not count for another.
    other = staff!(:admin)
    enrol!(other)

    assert redirected_to?(
             req(:get, "/support/admin/departments", other, session: passed),
             "/support/two-factor/challenge"
           )
  end

  test "the token API is not challenged" do
    on!()
    Application.put_env(:escalated, :api_tokens_enabled, true)
    agent = staff!(:agent)
    enrol!(agent)
    {:ok, %{plain_text_token: plain}} = ApiTokenService.create(agent.id, "CI", ["agent"], nil)

    conn =
      conn(:get, "/support/api/v1/tickets")
      |> init_test_session(%{})
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer " <> plain)
      |> Router.call(Router.init([]))

    assert conn.status == 200
  end

  # --- Enrolment ---------------------------------------------------------------

  test "an agent (not only an admin) enrols through the page" do
    on!()
    agent = staff!(:agent)

    setup = req(:post, "/support/admin/settings/two-factor/setup", agent)
    assert redirected_to?(setup, "/support/admin/settings/two-factor")

    %{qr_uri: qr_uri, recovery_codes: codes} =
      Phoenix.Flash.get(setup.assigns.flash, :two_factor_setup)

    assert qr_uri =~ ~r/^otpauth:\/\/totp\//
    assert length(codes) == 8

    secret =
      qr_uri |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("secret")

    {:ok, secret} = Base.decode32(secret, padding: false)

    props =
      page!(
        req(:get, "/support/admin/settings/two-factor", agent, session: session(setup)),
        "Escalated/Admin/Settings/TwoFactor"
      )

    assert props["pending"] == true
    assert props["enabled"] == false

    # Stored encrypted, never as the plain secret or codes.
    [{raw_secret, raw_codes}] =
      repo().all(
        from(t in TwoFactor.__schema__(:source),
          where: t.user_id == ^agent.id,
          select: {t.secret, t.recovery_codes}
        )
      )

    refute raw_secret =~ Base.encode32(secret, padding: false)
    refute inspect(raw_codes) =~ hd(codes)

    bad = req(:post, "/support/admin/settings/two-factor/confirm", agent, body: %{"code" => "12"})
    assert get_session(bad, "inertia_errors")["code"]

    confirm =
      req(:post, "/support/admin/settings/two-factor/confirm", agent,
        body: %{"code" => totp(secret)},
        session: session(setup)
      )

    assert redirected_to?(confirm, "/support/admin/settings/two-factor")

    assert Phoenix.Flash.get(confirm.assigns.flash, :two_factor_confirmed) == %{
             recovery_codes: codes
           }

    # Confirming counts as passing the challenge for this sign-in.
    assert req(:get, "/support/agent/dashboard", agent, session: session(confirm)).status == 200
    # A new sign-in is challenged.
    assert redirected_to?(
             req(:get, "/support/agent/dashboard", agent),
             "/support/two-factor/challenge"
           )

    props =
      page!(
        req(:get, "/support/admin/settings/two-factor", agent, session: session(confirm)),
        "Escalated/Admin/Settings/TwoFactor"
      )

    assert props["enabled"] == true
    # Only the one-time setup flash ever carries the secret; the page props do not.
    refute Jason.encode!(Map.drop(props, ["flash"])) =~ Base.encode32(secret, padding: false)

    # Setting up again while enabled is refused; disabling removes it.
    req(:post, "/support/admin/settings/two-factor/setup", agent, session: session(confirm))
    assert TwoFactorService.confirmed_for(agent)

    disabled =
      req(:post, "/support/admin/settings/two-factor/disable", agent, session: session(confirm))

    assert redirected_to?(disabled, "/support/admin/settings/two-factor")
    refute TwoFactorService.confirmed_for(agent)
  end

  test "a customer cannot reach enrolment" do
    on!()
    customer = host_user!(%{name: "Customer"})
    assert req(:get, "/support/admin/settings/two-factor", customer).status == 403
  end

  # --- Required ----------------------------------------------------------------

  test "required: staff without an enrolment can reach only the enrolment page" do
    on!()
    Application.put_env(:escalated, :two_factor, required: true)
    agent = staff!(:agent)
    admin = staff!(:admin)

    assert redirected_to?(
             req(:get, "/support/agent/dashboard", agent),
             "/support/admin/settings/two-factor"
           )

    assert redirected_to?(
             req(:get, "/support/admin/departments", admin),
             "/support/admin/settings/two-factor"
           )

    json = req(:get, "/support/agent/tickets", agent, json: true)
    assert json.status == 403
    assert Jason.decode!(json.resp_body)["two_factor_required"] == true

    props =
      page!(
        req(:get, "/support/admin/settings/two-factor", agent),
        "Escalated/Admin/Settings/TwoFactor"
      )

    assert props["required"] == true

    shared =
      Jason.decode!(
        req(:get, "/support/admin/settings/two-factor", agent, router: SharedPropsRouter).resp_body
      )

    assert shared["props"]["escalated"]["two_factor_required"] == true

    # Once enrolled (and through the challenge), everything opens up.
    %{secret: secret} = enrol!(agent)

    assert req(:get, "/support/agent/dashboard", agent, session: pass!(agent, secret)).status ==
             200
  end

  test "not required: staff without an enrolment use everything" do
    on!()
    agent = staff!(:agent)
    assert req(:get, "/support/agent/dashboard", agent).status == 200

    shared =
      Jason.decode!(
        req(:get, "/support/agent/dashboard", agent, router: SharedPropsRouter).resp_body
      )

    assert shared["props"]["escalated"]["two_factor_required"] == false
  end

  test "the two_factor_required setting wins over config, and env sets the default" do
    on!()
    agent = staff!(:agent)

    System.put_env("ESCALATED_TWO_FACTOR_REQUIRED", "true")
    assert TwoFactorService.required?()

    Application.put_env(:escalated, :two_factor, required: false)
    refute TwoFactorService.required?()

    admin = staff!(:admin)

    assert req(:post, "/support/admin/settings", admin, body: %{"two_factor_required" => true}).status in [
             302,
             303
           ]

    assert TwoFactorService.required?()

    assert redirected_to?(
             req(:get, "/support/agent/dashboard", agent),
             "/support/admin/settings/two-factor"
           )

    {:ok, _} = GeneralSettings.update(%{"two_factor_required" => false})
    refute TwoFactorService.required?()

    # The setting does nothing while the switch is off.
    {:ok, _} = GeneralSettings.update(%{"two_factor_required" => true})
    Application.put_env(:escalated, :access, two_factor: false)
    refute TwoFactorService.required?()
    assert req(:get, "/support/agent/dashboard", agent).status == 200
  end

  # --- Lost device -------------------------------------------------------------

  test "mix escalated.two_factor.reset removes a user's enrolment" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    agent = staff!(:agent)
    enrol!(agent)

    Mix.Tasks.Escalated.TwoFactor.Reset.run([agent.email])
    refute TwoFactorService.confirmed_for(agent)
    assert_received {:mix_shell, :info, ["Removed the two-factor enrolment" <> _]}

    assert_raise Mix.Error, ~r/No user/, fn ->
      Mix.Tasks.Escalated.TwoFactor.Reset.run(["nobody@example.test"])
    end
  end
end
