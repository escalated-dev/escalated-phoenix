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
| Two-factor | `access: [two_factor: true]` | `ESCALATED_TWO_FACTOR` | Not yet; always reported off |
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
