# Configuration

## Configuration

Attachment download routes require an authenticated requester or agent. Internal
reply files are available only to agents. Sessions and the configured host
`api_token_validator` are supported. Local files must be regular files within
`:upload_dir` (default `priv/uploads`), with no symlink components. Keep that
directory private and outside static web serving.

For external storage, configure `:attachment_download_url` as a two-argument
function receiving the attachment and an expiry in seconds (300). It must return
`{:ok, https_url}` for a signed, private download or `{:error, reason}`. The host's
storage adapter must honor that expiry. The callback runs only after ticket and
reply authorization. Missing configuration returns 503; the package does not
redirect to the stored permanent URL. Existing publicly served files need to be
moved or made private by the host; changing this route does not revoke URLs
already issued by a storage provider. Verified guest grants can authorize public
attachments on their ticket; private storage redirects expire within the shorter
of 300 seconds and the remaining grant lifetime. Internal-note files remain
staff-only. Permanent legacy guest tokens are rejected.

### Staff authorization

`Escalated.Permissions.admin?/1` and `agent?/1` determine access consistently
for admin/agent routes, ticket APIs and realtime channels. The host must supply
an authenticated user with an ID. Configured `admin_check` and `agent_check`
callbacks are authoritative for their respective capability and must return
the boolean `true` to grant it. A denied or invalid callback never falls back to
stored roles.

Without callbacks, admin access uses the host `is_admin` flag or an active
Escalated admin profile. Agent access uses effective admin access, the host
`is_agent` flag, or an active agent/admin profile. Host flags accept `true`, `1`,
`"1"`, or `"true"`; atom keys take precedence if both atom and string keys exist.
An inactive profile removes profile-derived access; it does not override an
independent host role. An explicit `agent_check` denial still denies agent
routes for administrators. Newsletter permission callbacks use the same strict
boolean rule and retain their precedence over admin/permission defaults.

Merchant mode independently requires current host membership. Without an explicit
host callback, staff access then requires an active **tenant-local** agent/admin
profile; a host-wide staff flag never grants a seat in another merchant.

Ticket requesters retain access to safe public events on their own ticket channel.
Guest chat joins require a verified, unexpired chat grant in single-tenant mode.
The queue and per-agent topics require staff access. Membership, ownership and
guest grants are rechecked before processing or delivering messages. Merchant
guest chat uses the authenticated polling routes; anonymous merchant sockets are
refused. See [merchant and guest integration](merchant-and-guest-access.md).

### Persistent admin preferences

The general Settings page supports four durable boolean preferences:
`knowledge_base_enabled`, `knowledge_base_public`,
`knowledge_base_feedback_enabled` (all default false), and `show_powered_by`
(default true). Saved values override host configuration across requests and
process restarts. The existing settings migrations must be applied, including
the June 2026 migration adding the `type` column and the September 30, 2026
merchant/guest migrations. Apply every package migration before using this code,
including on existing single-tenant installations.

Use a shared frontend build containing
[settings capabilities (PR #185)](https://github.com/escalated-dev/escalated/pull/185)
before upgrading this page. It renders `Escalated/Admin/Settings`, advertises only
those four fields, and supplies an explicit POST update URL. Other controls stay
hidden until their Phoenix behavior is implemented. Unsupported fields and
invalid booleans reject the whole update. Existing nested PUT requests remain
supported for those same fields.

Admin routes require the host's `admin_check` callback to return `true`, or, when
no callback is configured, an admin host flag or Escalated admin profile. A
signed-in customer alone cannot read or save settings. Nonpublic knowledge bases
require an authenticated host user; disabling feedback also blocks direct POSTs.
The host's own authentication pipeline can further restrict public access.

Add the following to your `config/config.exs`:

```elixir
config :escalated,
  repo: MyApp.Repo,
  user_schema: MyApp.Accounts.User,
  route_prefix: "/support",
  table_prefix: "escalated_",
  ui_enabled: true,
  admin_check: &MyApp.Accounts.admin?/1,
  agent_check: &MyApp.Accounts.agent?/1
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `repo` | *required* | The Ecto repo Escalated's own tables live on |
| `user_repo` | `repo` | The Ecto repo your `user_schema` lives on. Only set it when that is a different database — see [Separate databases](#separate-databases) |
| `user_schema` | *required* | Your User schema module |
| `route_prefix` | `"/support"` | URL prefix for all Escalated routes; set it to the prefix you pass to `escalated_routes/2` (the shared `ziggy` route table is built from it) |
| `route_overrides` | `%{}` | Your own paths for route names the shared pages call: `%{"login" => "/users/log_in"}`, `%{name => %{uri: ..., methods: [...]}}`, or `nil` to drop one. See [UI Rendering](#ui-rendering) |
| `table_prefix` | `"escalated_"` | Database table name prefix |
| `user_key_type` | `:integer` | Column type for host-user references: `:integer` (default), `:binary_id` (UUID), or `:string`. Set to match your `user_schema` primary key so UUID/string-keyed apps migrate cleanly. |
| `ui_enabled` | `true` | Mount Inertia.js UI routes |
| `ui` | `[]` | `embed:` -- embed the admin in your own admin panel, off by default: `enabled`, `mode`, `prefix`, `middleware`, `replace_admin_gate`, `layout`, `root_view`, `frame_ancestors`. See [embedding the admin](embedding-admin.md) |
| `api_enabled` | `false` | Mount JSON API routes |
| `guest_tickets_enabled` | `true` | Allow guest ticket codes, lookups and creates on the mobile guest API (`false` answers them 403) |
| `api_tokens_enabled` | `false` | Accept Escalated-issued API tokens on the ticket API ([API tokens](api-tokens.md)) |
| `access` | `[]` | Install-level access switches, all off by default: `roles_permissions` (env `ESCALATED_ROLES_PERMISSIONS`), `two_factor` (env `ESCALATED_TWO_FACTOR`), `sso` (env `ESCALATED_SSO`). See [access control](access-control.md) |
| `sso` | `[]` | Single sign-on rules: `sign_in` (your callback that signs the resolved user in), `base_url`, `jwt_audience`, `clock_skew`, `create_users`, `sync_roles`, `redirect_to`, `http_adapter`. Mount `escalated_sso_routes/1` outside your sign-in pipeline. See [access control](access-control.md#single-sign-on) |
| `two_factor` | `[]` | `required` (env `ESCALATED_TWO_FACTOR_REQUIRED`), `issuer` (default `"Escalated"`), `login_session_key` (default `"user_token"`). See [access control](access-control.md#two-factor-authentication) |
| `two_factor_secret` | `nil` | 32+ byte key for encrypting two-factor secrets and recovery codes (falls back to `guest_access_secret`) |
| `admin_check` | `nil` | Function `(user -> boolean)` for admin access |
| `agent_check` | `nil` | Function `(user -> boolean)` for agent access |
| `default_priority` | `:medium` | Default ticket priority |
| `allow_customer_close` | `true` | Allow customers to close their tickets |
| `sla` | `%{enabled: true, ...}` | SLA configuration map |
| `ticket_subjects` | `%{types: [], resolver: nil}` | Allowlisted host subject types and resolver for attach/API + UI serialization |

### Separate databases

In Ecto the repo *is* the connection, so pointing `:repo` at a second repo is
all it takes to keep Escalated's tables out of your primary database — a schema
shared with a legacy system, a separate reporting store, or a database you would
simply rather not mix support data into.

Your users do not move with it. Tell Escalated where they stayed:

```elixir
config :escalated,
  repo: MyApp.SupportRepo,      # Escalated's tables
  user_repo: MyApp.Repo,        # your users
  user_schema: MyApp.Accounts.User
```

Set neither and nothing changes: `user_repo` falls back to `repo`, which is the
single-database setup every host starts with.

Both repos must be started by your application's supervision tree, and
`MyApp.SupportRepo` is the one you run Escalated's migrations against:

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

#### What Escalated does not do

**No query joins the two.** No database can join across two connections, and
Escalated does not try. There is no `belongs_to` from any Escalated schema to
your user schema; a ticket's `requester_id`, `assigned_to` and a reply's
`author_id` are plain unconstrained columns, and every user lookup is a separate
query on `user_repo`. That is also why there is no foreign key to add — and why
deleting a user in your app leaves their tickets intact, resolving to a blank
requester rather than failing.

Filtering or sorting Escalated's tables *by* a user's own columns is therefore
not possible across a split. Agent load, skill routing and mention search all
work because they resolve ids on one repo and names on the other, in two steps.

**Your users are never written by the split.** The one place Escalated writes to
a host user is the admin panel's role toggle, which goes to `user_repo` like
every other user query.

## UI Rendering

By default, Escalated renders pages via [Inertia.js](https://github.com/inertiajs/inertia-phoenix) when `inertia` is installed. If Inertia is not available, controllers fall back to JSON responses.

> **Pipeline requirement.** `inertia` reads `assigns.flash` when it builds a response, so your browser pipeline must run `fetch_flash` (and a session) before `Inertia.Plug`:
>
> ```elixir
> pipeline :browser do
>   plug :fetch_session
>   plug :fetch_flash
>   plug Inertia.Plug
> end
> ```
>
> Escalated previously depended on `inertia_phoenix`, which did not require this. That package is retired (last released 2023) and pinned two vulnerable transitive dependencies, so it was replaced with the officially maintained `inertia` package.

You can build your own frontend components that consume the Inertia page props, or use the JSON API directly.

This source line uses the Inertia Phoenix 2.6 protocol. An upgrade to Inertia
Phoenix 3 also requires client-side `@inertiajs/*` 3, a frontend release that
reads top-level `page.flash`, and a bootstrap that reads the JSON script element
instead of the old `data-page` attribute. The shared frontend source includes
that flash support after escalated-dev/escalated#202; deploying an older npm
release does not pick up a source-only change.

For Inertia 3, set `http.xsrfHeaderName` to `'x-csrf-token'` in the
`createInertiaApp` options so Phoenix receives its expected CSRF header. Axios
defaults no longer configure Inertia 3's HTTP client. Hosts using the default
Node.js SSR adapter must also explicitly depend on `nodejs` 3.1.4+ below 4.0.
Review the [upstream migration guide](https://github.com/inertiajs/inertia-phoenix/blob/v3.0.1/guides/upgrading_to_v3.md)
before changing the server adapter major.

### Named routes (`route()`)

The shared pages call Laravel-style named routes, `route('escalated.agent.tickets.show', ticket)`.
Escalated ships those names with this package's paths (`Escalated.Routes`)
and shares them on every Escalated Inertia page as the `ziggy` prop, in the
shape ziggy-js reads. Install the matching `route()` helper once in your root
layout, in the body, before your app's script runs:

```heex
<body>
  {@inner_content}
  {Escalated.Routes.helper_tag(nonce: assigns[:csp_nonce])}
</body>
```

(`Escalated.Routes.helper_script/0` returns the bare JavaScript if you bundle
it yourself.) The helper does nothing when `window.route` already exists, so a
page that loads ziggy-js or your own shim keeps it, and it reads
`window.Ziggy.routes` before the shared prop. An unknown name logs a warning
and returns `#`.

You no longer map the names yourself. To change one, your mapping wins:

- `config :escalated, route_overrides: %{"login" => "/users/log_in"}` replaces
  or adds single names (`%{uri: ..., methods: [...]}` for a non-GET route,
  `nil` to drop one). `login` is yours to map: Escalated does not own sign-in.
- A `ziggy` prop your own pipeline shares (`Inertia.Controller.assign_prop/3`)
  is used instead of the built-in table.

The URIs follow `route_prefix`, which must match the prefix you mount
`escalated_routes/2` at. The live chat bar's `escalated.admin.chat.transfer`
and `escalated.admin.chat.end` point at `{prefix}/agent/chat/:session/...`,
keyed by the ticket's `chat_session_id`.

Maintainers can run `MIX_ENV=test mix run --no-start scripts/verify_package.exs`
to build and unpack the actual Hex package, install it in isolated hosts, audit
the resolved graph, test JSON fallback without the optional Inertia dependency,
and verify that a host pinning vulnerable Decimal 3.1.1 cannot resolve. Evidence
is written to `tmp/package-verification/`. The normal test suite also exercises
HTML/XHR bootstrapping, escaping, session flash, CSRF, and redirect contracts
through a host Phoenix router.

## Public request limits

Guest ticket creation, token lookup and guest ratings share a default budget of
20 requests per minute per remote IP. Widget and chat routes share a separate
20-request budget. An open guest chat polls every three seconds, so its message
polling, sending and typing routes have their own budget instead: 90 requests per
minute per chat capability and network, and 300 per network across all chat
capabilities, so changing guessed tokens cannot mint fresh budgets. IPv6 clients
are counted per /64. Limits run before controller work and return HTTP 429 with
`Retry-After` and `Cache-Control: no-store` when exhausted.

On top of those shared budgets, the guest writes have per-IP limits of their own:
5 ticket creations (`POST /widget/tickets`, `POST /api/v1/guest/tickets`,
`POST /api/v1/mobile/guest/tickets` and `POST /api/v1/mobile/guest/verification`)
and 10 replies (`POST /widget/tickets/:reference/reply`,
`POST /api/v1/guest/tickets/:token/replies`,
`POST /api/v1/mobile/guest/tickets/:token/replies` and
`POST /api/v1/mobile/guest/lookup`) per minute, each with its own
counter shared by every surface. The reply limit runs before the guest token is resolved, so wrong-token
guesses count too. Set `enabled: false` only when you already throttle these
routes upstream.

```elixir
config :escalated,
  guest_rate_limit: %{max_requests: 20, window_ms: 60_000},
  widget_rate_limit: %{max_requests: 20, window_ms: 60_000},
  widget_chat_rate_limit: %{max_requests: 90, max_requests_per_ip: 300, window_ms: 60_000},
  guest_submission_rate_limit: %{enabled: true, tickets_per_minute: 5, replies_per_minute: 10}
```

The built-in fixed-window limiter is supervised by the Escalated OTP application,
serializes concurrent admission, expires idle counters, and caps storage at
50,000 IP/bucket entries. Limits are **per node** and reset when its process or
application restarts. A full store, unavailable backend or invalid configuration
returns HTTP 503 instead of allowing uncounted requests.

Multi-node hosts can configure `rate_limit_backend: MyApp.SharedRateLimiter`.
Its `check(bucket, key, max_requests, window_ms)` callback must atomically
return `:allow`, `{:deny, positive_retry_after_ms}`, or `{:error, reason}`. The
buckets `:guest`, `:widget`, `:guest_ticket`, `:guest_reply` and
`:widget_chat_network` key on the client's IP
tuple (an IPv6 address with its last 64 bits zeroed); `:widget_chat` keys on
`{ip_tuple, capability_hash}`, a hash of the chat capability, never the token.
Only a host's trusted-proxy pipeline should rewrite `conn.remote_ip`; Escalated
does not trust `X-Forwarded-For` itself. **Behind a proxy or load balancer,
configure trusted proxies (for example `Plug.RewriteOn` or the `remote_ip`
library) before the router, or every guest shares the proxy's address.** Edge rate limits remain useful for
distributed traffic. Guest email proof also has a database-backed mailbox budget
shared across tenants and nodes. Setup and request shapes are documented in
[merchant and guest integration](merchant-and-guest-access.md).

## Plugs

Escalated provides plugs for authorization:

- `Escalated.Plugs.EnsureAgent` -- requires the user to pass the configured `agent_check`
- `Escalated.Plugs.EnsureAdmin` -- requires the user to pass the configured `admin_check`
- `Escalated.Plugs.ShareInertiaData` -- shares common Escalated data with Inertia pages

## Schemas

- `Escalated.Schemas.Ticket` -- support tickets with status, priority, SLA tracking
- `Escalated.Schemas.Reply` -- ticket replies and internal notes
- `Escalated.Schemas.Department` -- support departments/teams
- `Escalated.Schemas.Tag` -- ticket tags for categorization
- `Escalated.Schemas.SlaPolicy` -- SLA policies with per-priority targets
- `Escalated.Schemas.TicketActivity` -- audit log of ticket changes
- `Escalated.Schemas.AgentProfile` -- agent-specific profile data
