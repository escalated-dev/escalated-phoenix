# Access control: roles & permissions, two-factor, SSO

Escalated's roles & permissions, two-factor authentication and single sign-on
are **install-level switches**, off by default
([ADR 2026-10-29](https://github.com/escalated-dev/escalated-developer-context/blob/main/decisions/2026-10-29-configurable-access-features.md)).
While a switch is off its admin screens and routes answer 404 and nothing is
enforced; your `admin_check` / `agent_check` (or the host flags and agent
profiles) decide who may do what, exactly as before. While it is on, the
feature is enforced.

The switches are read from config, then the environment. No admin screen or
stored setting changes them.

```elixir
config :escalated,
  access: [roles_permissions: true]
```

| Feature | Config key | Env var | Status in this package |
|---|---|---|---|
| Roles & permissions | `access: [roles_permissions: true]` | `ESCALATED_ROLES_PERMISSIONS` | Enforced |
| Two-factor | `access: [two_factor: true]` | `ESCALATED_TWO_FACTOR` | Enforced |
| Single sign-on | `access: [sso: true]` | `ESCALATED_SSO` | Enforced (OAuth 2 / OIDC and JWT; SAML refused, see below) |

A config value, when set, wins over the env var. `Escalated.AccessFeatures`
reads them; `Escalated.Plugs.EnsureFeatureEnabled` answers 404 for a route
whose feature is off.

## Roles & permissions

### What is enforced

With the switch on, every admin, agent and staff API route needs a permission
**in addition to** the admin or agent gate for that area. A user's permissions
are the union of their Escalated roles' permissions (`role_user` and
`role_permissions`). Nothing else grants one: passing the admin gate, `is_admin`
or an agent profile's `role` gives no permissions by itself. Give users who
should have everything the `admin` role.

- The route to permission map is `Escalated.RoutePermissions`, keyed by
  controller and action. A route missing from it is refused, and a test checks
  every admin, agent and staff API route is in it.
- A status change needs `ticket.edit`, plus `ticket.close` when the new status
  is `resolved`, `closed` or `reopened`.
- Bulk actions need the permission of the action: `assign` needs
  `ticket.assign`, `delete` needs `ticket.delete`, the rest `ticket.edit`.
- Applying a macro needs `macro.view` and `ticket.edit`.
- The staff API (`/api/v1/tickets*`) checks the permissions of the user the
  request acts as: an API token's owner, or the user your
  `api_token_validator` returns.
- The newsletter screens check `newsletters.manage` and `newsletters.send` from
  the user's roles only while the switch is on (a `newsletter_permission_check`
  callback still takes precedence).

Failing a permission answers 403.

### Seeded roles

`mix escalated.seed_permissions` creates the permissions and three system
roles:

| Role | Permissions |
|---|---|
| `admin` | all |
| `agent` | `ticket.*`, `reply.*`, `kb.view`, `report.view`, `macro.view`, `macro.create`, `tag.view`, `custom_field.view`, `audit.view` |
| `light_agent` | `ticket.view`, `reply.create`, `reply.create_internal`, `kb.view`, `macro.view`, `tag.view` |

Seeding again keeps what roles already grant and adds anything missing.
Custom roles are made in **Admin > Roles**.

### Giving users roles

- From the command line: `mix escalated.roles.assign you@example.com admin`
  (email or ID, then the role slug; add `--tenant ID` with merchant tenancy).
- From the admin: `PUT {prefix}/admin/users/:user_id/roles` with `role_ids`
  (needs `role.manage`; replaces the user's roles). You cannot remove your own
  `role.manage`. While the switch is on, the users page receives each user's
  `roles` (slugs) and a `roles` list of `{id, name, slug}`.

### Turning it on

1. Run the migrations (`mix ecto.migrate`), which add `role_user`.
2. Seed the permissions: `mix escalated.seed_permissions`.
3. Give every staff user a role, starting with yourself:
   `mix escalated.roles.assign you@example.com admin`.
4. Set `ESCALATED_ROLES_PERMISSIONS=true` (or the config key) and restart.

Staff without a role can reach nothing until they get one.

### Shared props

With `Escalated.Plugs.ShareInertiaData` in your pipeline, every page gets
`escalated.features.roles_permissions` (and `two_factor`, `sso`) and
`escalated.permissions`: the user's slugs while on, `["*"]` for staff while
off, `[]` for everyone else.

## Two-factor authentication

### What is enforced

With `ESCALATED_TWO_FACTOR=true` (or `access: [two_factor: true]`):

- **Enrolment.** Every staff user (agents too, not only admins) can set up
  TOTP at `{prefix}/admin/settings/two-factor`
  (`Escalated/Admin/Settings/TwoFactor`, props `enabled`, `pending`,
  `required`): `POST .../setup` issues a 160-bit secret, an `otpauth://` URI
  and eight recovery codes (flash `two_factor_setup`); `POST .../confirm`
  takes a 6-digit `code` (flash `two_factor_confirmed`); `POST .../disable`
  removes the enrolment. Secrets and recovery codes are stored encrypted
  under `:two_factor_secret` (or `:guest_access_secret`). TOTP is RFC 6238
  (SHA-1, 6 digits, 30 s) via `nimble_totp`, accepting one step of drift.
  The page is in `Escalated.RoutePermissions` with no permission, so it
  stays open while roles & permissions is on.
- **Challenge.** Escalated does not own your login form. After your app
  signs someone in, a staff user with a confirmed enrolment who opens any
  admin or agent route is redirected to `GET {prefix}/two-factor/challenge`
  (`Escalated/Auth/TwoFactorChallenge`, props `action`, `error`). It posts
  `code` or `recovery_code` to `POST {prefix}/two-factor/challenge`.
  Success renews the session ID and returns to the page they asked for;
  failure is a validation error on the field sent. JSON requests get 403 with
  `two_factor_required: true` instead of a redirect.
- **Once per login.** The pass is stored in the session with the user's ID
  and a fingerprint of the session's login token (`"user_token"`, which
  `mix phx.gen.auth` writes on every login; change it with
  `two_factor: [login_session_key: "..."]`). A new login, or another user, is
  challenged again. You can also call `Escalated.TwoFactorSession.forget/1`
  from your login and logout.
- A code works once: its time step is recorded (`two_factors.last_used_step`)
  and that step or any earlier one is refused. Recovery codes are removed
  when used.
- The challenge is throttled to 5 attempts a minute per user
  (`two_factor_rate_limit: %{max_requests: 5, window_ms: 60_000}`).
- **Required.** `two_factor: [required: true]` (env
  `ESCALATED_TWO_FACTOR_REQUIRED`), or the `two_factor_required` general
  setting (`POST {prefix}/admin/settings`; the setting wins once saved),
  sends staff without an enrolment to the enrolment page, and they can use
  nothing else until they enrol. The shared prop
  `escalated.two_factor_required` is true for a user in that position.
- **Lost device.** `mix escalated.two_factor.reset you@example.com` removes a
  user's enrolment (`--tenant ID` with merchant tenancy).
- The token API is not session-based and is not challenged. Your browser
  pipeline must fetch the session (`:fetch_session`) for the challenge to
  apply.

While the switch is off, the enrolment and challenge routes answer 404 and
nobody is challenged. Enrolments are kept.

The shared pages call these route names through your `window.route` shim:

| Route name | Path |
|---|---|
| `escalated.admin.two-factor.index` | `GET {prefix}/admin/settings/two-factor` |
| `escalated.admin.two-factor.setup` | `POST {prefix}/admin/settings/two-factor/setup` |
| `escalated.admin.two-factor.confirm` | `POST {prefix}/admin/settings/two-factor/confirm` |
| `escalated.admin.two-factor.disable` | `POST {prefix}/admin/settings/two-factor/disable` |
| `escalated.two-factor.challenge` | `GET {prefix}/two-factor/challenge` |
| `escalated.two-factor.verify` | `POST {prefix}/two-factor/challenge` |

### Turning it on

1. Set `:two_factor_secret` to a random value of 32 bytes or more and keep
   it: changing it makes existing enrolments unreadable, and those users
   then need `mix escalated.two_factor.reset`.
2. Run the migrations (`mix ecto.migrate`), which add
   `two_factors.last_used_step`.
3. Set `ESCALATED_TWO_FACTOR=true` and restart. Anyone who enrolled before is
   challenged from their next visit.
4. Optionally require it, after telling your staff.

## Single sign-on

### What is enforced

With `ESCALATED_SSO=true` (or `access: [sso: true]`), people sign in at
`GET {prefix}/sso/login` through the provider chosen in **Admin > Settings >
SSO** (`Escalated/Admin/Settings/SsoSettings`, `sso_provider`: `none`,
`oauth` or `jwt`). With `none`, and for any provider other than the chosen
one, the sign-in routes answer 404.

| Route | Laravel name | Use |
|---|---|---|
| `GET {prefix}/sso/login` | `escalated.sso.login` | Start sign-in |
| `GET {prefix}/sso/saml/metadata` | `escalated.sso.saml.metadata` | SAML SP metadata (refused, see below) |
| `POST {prefix}/sso/saml/acs` | `escalated.sso.saml.acs` | SAML assertion consumer (refused, see below) |
| `GET {prefix}/sso/oauth/callback` | `escalated.sso.oauth.callback` | OAuth 2 / OIDC redirect URI |
| `GET\|POST {prefix}/sso/jwt/callback` | `escalated.sso.jwt.callback` | JWT hand-off (`jwt` parameter) |
| `GET\|POST {prefix}/admin/settings/sso` | `escalated.admin.settings.sso(.update)` | The provider and its fields |

The settings page receives `settings` (the `sso_*` keys; the JWT secret and
the OAuth client secret are masked as `********`, and posting the mask back
keeps the stored value) and `endpoints` (`login`, `sp_entity_id`,
`metadata`, `acs`, `oauth_redirect`, `jwt_callback`) to give the identity
provider. It needs `settings.view` / `settings.manage` while roles &
permissions is on.

**OAuth 2 / OIDC** (`assent`). Authorization-code flow with a single-use
`state` kept in the session and PKCE `S256`. The code is exchanged at
`sso_oauth_token_url` server to server (with the client secret, when one is
set) and the profile read from `sso_oauth_userinfo_url` with the access
token. A missing or mismatched `state`, an IdP `error`, or a profile with
`email_verified: false` is refused. Requests use `:httpc` with the peer
certificate and host name verified; name another `Assent.HTTPAdapter` with
`sso: [http_adapter: ...]`.

**JWT** (`joken` on `jose`). The IdP sends the user back to the callback with
`jwt` (query or form). The algorithm is pinned to `sso_jwt_algorithm` (HS256,
HS384 or HS512 with the secret; RS256, RS384 or RS512 with the PEM public key
in the same field), so `alg: none` and algorithm switching are refused.
`exp` is required, `nbf` and `iat` must not be in the future, `aud` must name
`sso: [jwt_audience:]` (default: the base URL), and `jti` is required and
works once: it is kept in `sso_message_ids` until it expires. Clock skew is
`sso: [clock_skew:]` seconds (default 120, at most 300). `sso/login` sends
the browser to `sso_login_url` (or `sso_url`) with `return_to` set to the
callback.

**SAML is not available in this package yet.** No maintained Elixir SAML
library meets the ADR's checks on the Elixir and OTP versions this package
supports: `esaml`/`samly` carry open advisories (atom exhaustion, XXE,
unbounded decompression) and their `cowlib` no longer builds on OTP 26, and
the newer libraries need a later Elixir. Rather than hand-roll XML signature
checks, the settings page refuses `saml`, and with a stored `saml` provider
`sso/login`, the metadata and every posted response are refused.

### Users and roles

- The email comes from the `sso_attr_email` claim (default `email`), the name
  from `sso_attr_name`, the role from `sso_attr_role`. OAuth claim names may
  be dotted paths into the profile.
- The email is matched to a host user case-insensitively. An unknown email is
  refused unless `sso: [create_users: true]` (`ESCALATED_SSO_CREATE_USERS`),
  which creates one: through your `sso: [create_user: {Mod, :fun}]` callback
  (given `%{email, name}`, returning `{:ok, user}`) when set, otherwise by
  inserting your user schema with `email` and `name` only, so it has no usable
  password.
- With roles & permissions on and `sso: [sync_roles: true]`
  (`ESCALATED_SSO_SYNC_ROLES`), a role value naming an Escalated role slug
  replaces the user's roles; an unknown value changes nothing. SSO never
  changes your admin or agent gates.
- **Signing in is yours.** Escalated resolves the user, clears the two-factor
  mark (`Escalated.TwoFactorSession.forget/1`, so the challenge still
  applies), renews the session and calls your `sso: [sign_in: ...]` callback
  with `(conn, user)`. It must sign the user in and return the conn, for
  example by writing a fresh session token the way `mix phx.gen.auth`'s
  `log_in_user/2` does (if it sends a response or redirects, that is used).
  Without the callback every sign-in is refused. The browser then goes to
  `sso: [redirect_to:]`, the session's `user_return_to` (a local path), or
  the agent dashboard.
- Every refusal answers 403 with a generic message and logs the reason.

Escalated does not switch off your password login.

### Mounting the routes

People who use the SSO routes are not signed in yet, and the IdP posts to
the JWT callback from its own site, so mount them in a pipeline without your
sign-in requirement and without `:protect_from_forgery` (the OAuth `state`
and the signed, single-use JWT are what authenticate those requests), and
leave them out of `escalated_routes/2`:

```elixir
pipeline :escalated_sso do
  plug :accepts, ["html", "json"]
  plug :fetch_session
end

scope "/" do
  pipe_through :escalated_sso
  escalated_sso_routes("/support")
end

scope "/" do
  pipe_through [:browser, :authenticated]
  escalated_routes("/support", sso: false)
end
```

### Configuration

```elixir
config :escalated,
  access: [sso: true],
  sso: [
    sign_in: {MyAppWeb.UserAuth, :escalated_sso_sign_in},
    base_url: "https://help.example.com", # ESCALATED_SSO_BASE_URL; default: your endpoint's URL
    jwt_audience: nil,                    # ESCALATED_SSO_JWT_AUDIENCE; default: base_url
    clock_skew: 120,                      # ESCALATED_SSO_CLOCK_SKEW
    create_users: false,                  # ESCALATED_SSO_CREATE_USERS
    sync_roles: false,                    # ESCALATED_SSO_SYNC_ROLES
    redirect_to: nil,                     # ESCALATED_SSO_REDIRECT_TO
    sp_entity_id: nil                     # ESCALATED_SSO_SP_ENTITY_ID (shown on the settings page)
  ]
```

`base_url` is what the callback URLs given to the IdP, and the default JWT
audience, are built from; set it when your app sits behind a proxy.

### Turning it on

1. Run the migrations (`mix ecto.migrate`), which create `sso_message_ids`.
2. Add the `sign_in` callback and mount the routes as above.
3. Set `ESCALATED_SSO=true`, choose the provider in Admin > Settings > SSO
   and give the IdP the endpoints shown there.
4. Decide on `create_users` and `sync_roles`.
