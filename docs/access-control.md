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
| Single sign-on | `access: [sso: true]` | `ESCALATED_SSO` | Not yet; always reported off |

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
