<p align="center">
  <a href="docs/translations/README.ar.md">العربية</a> •
  <a href="docs/translations/README.de.md">Deutsch</a> •
  <b>English</b> •
  <a href="docs/translations/README.es.md">Español</a> •
  <a href="docs/translations/README.fr.md">Français</a> •
  <a href="docs/translations/README.it.md">Italiano</a> •
  <a href="docs/translations/README.ja.md">日本語</a> •
  <a href="docs/translations/README.ko.md">한국어</a> •
  <a href="docs/translations/README.nl.md">Nederlands</a> •
  <a href="docs/translations/README.pl.md">Polski</a> •
  <a href="docs/translations/README.pt-BR.md">Português (BR)</a> •
  <a href="docs/translations/README.ru.md">Русский</a> •
  <a href="docs/translations/README.tr.md">Türkçe</a> •
  <a href="docs/translations/README.zh-CN.md">简体中文</a>
</p>

# Escalated for Phoenix

[![Views](https://hits.sh/github.com/escalated-dev/escalated-phoenix.svg?style=flat&label=views&color=007ec6)](https://hits.sh/github.com/escalated-dev/escalated-phoenix/)

Embeddable helpdesk and support ticket system for Phoenix applications. Drop-in support tickets, departments, SLA policies, and agent management as a Hex package.

## Features

- **Ticket lifecycle** — Create, assign, reply, resolve, close, reopen with configurable status transitions
- **SLA engine** — Per-priority response and resolution targets, business hours calculation, automatic breach detection
- **Agent dashboard** — Ticket queue with filters, internal notes, canned responses
- **Customer portal** — Self-service ticket creation, replies, and status tracking
- **Admin panel** — Manage departments, SLA policies, tags, and view reports
- **File attachments** — Drag-and-drop uploads with configurable storage and size limits
- **Activity timeline** — Full audit log of every action on every ticket
- **Department routing** — Organize agents into departments with auto-assignment
- **Tagging system** — Categorize tickets with colored tags
- **Ticket splitting** — Split a reply into a new standalone ticket while preserving the original context
- **Ticket snooze** — Snooze tickets with presets (1h, 4h, tomorrow, next week); `mix escalated.wake_snoozed_tickets` Mix task auto-wakes them on schedule
- **Saved views / custom queues** — Save, name, and share filter presets as reusable ticket views
- **Embeddable support widget** — Lightweight `<script>` widget with KB search, ticket form, and status check
- **Email threading** — Outbound emails include proper `In-Reply-To` and `References` headers for correct threading in mail clients
- **Inbound email** — Single webhook endpoint with Postmark + Mailgun + AWS SES parsers, signed Reply-To verification, and Message-ID-based ticket resolution
- **Branded email templates** — Configurable logo, primary color, and footer text for all outbound emails
- **Real-time broadcasting** — Opt-in broadcasting via Phoenix PubSub with automatic polling fallback
- **Knowledge base toggle** — Enable or disable the public knowledge base from admin settings
- **Merchant tenancy** — Tenant-scoped data access, staff seats, jobs and realtime topics, with explicit legacy-data assignment
- **Verified guest access** — Email proof, expiring encrypted grants, private guest attachments and host-resolved tracking lookup

## Installation

Add `escalated` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:escalated, "~> 0.1.0", hex: :escalated_phoenix}
  ]
end
```

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
refused. See [merchant and guest integration](docs/merchant-and-guest-access.md).

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
| `route_prefix` | `"/support"` | URL prefix for all Escalated routes |
| `table_prefix` | `"escalated_"` | Database table name prefix |
| `user_key_type` | `:integer` | Column type for host-user references: `:integer` (default), `:binary_id` (UUID), or `:string`. Set to match your `user_schema` primary key so UUID/string-keyed apps migrate cleanly. |
| `ui_enabled` | `true` | Mount Inertia.js UI routes |
| `api_enabled` | `false` | Mount JSON API routes |
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

## Ticket subjects

A ticket has a **requester** (who raised it) and a **subject line** (free text). Tickets can also be *about* host-app entities — a Project, Customer, asset — that are not people. Attach them as ticket **subjects** so agents see what the ticket concerns and can jump into your app.

Implement the `Escalated.TicketSubject` behaviour on any host struct and register a resolver:

```elixir
defmodule MyApp.Projects.Project do
  @behaviour Escalated.TicketSubject

  def ticket_subject_title(project), do: project.name
  def ticket_subject_subtitle(project), do: "Project · #{project.account}"
  def ticket_subject_url(project), do: Routes.project_url(MyAppWeb.Endpoint, :show, project)
  def ticket_subject_color(_), do: "#2563eb"
  def ticket_subject_icon(_), do: "folder"
end

# config/config.exs
config :escalated,
  ticket_subjects: [
    types: ["project", "customer"],
    resolver: &MyApp.TicketSubjects.resolve/2
  ]
```

Attach, detach, or sync from application code:

```elixir
Escalated.Services.TicketSubjectService.attach_subject(ticket, "project", "prj_9f1c", role: "project")
Escalated.Services.TicketSubjectService.detach_subject(ticket, "project", "prj_9f1c")
Escalated.Services.TicketSubjectService.sync_subjects(ticket, [{"project", "b", "primary"}, {"customer", "c"}])
```

Each link is serialized on ticket detail JSON as
`{ type, id, role, title, subtitle, url, color, icon, missing }`.
Admin routes `POST` / `DELETE` … `/admin/tickets/:reference/subjects` accept only allowlisted types and require the resolver to return a struct.

`subject_id` is stored as a string (not `Escalated.UserKey`) so integer, UUID, and custom string host keys all work.

## Database Setup

Run every package migration against the configured support repository:

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Use `MyApp.Repo` instead if support and host records share that repository. If
your host copies package migrations into its own migration directory, preserve
all original version numbers and include every later migration; copying only
the initial table migration does not create the current schema. Upgrades also
require the September 30, 2026 merchant and guest migrations. See the
[upgrade guide](docs/merchant-and-guest-access.md#provisioning-and-upgrading)
before assigning legacy data or enabling public guest access.

## Router Setup

Mount Escalated routes in your Phoenix router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use Escalated.Router

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  scope "/" do
    pipe_through [:browser, :authenticated]
    escalated_routes("/support")
  end
end
```

This mounts:

- **Customer routes** at `/support/tickets/*` -- view/create/reply to the signed-in user's own tickets. Creation accepts subject, description, priority, ticket type and department; requester identity and staff-controlled fields come from the server. CSAT by reference requires the authenticated requester. API reply authors are taken from the authenticated agent.
- **Agent routes** at `/support/agent/*` -- agent dashboard and ticket management
- **Admin routes** at `/support/admin/*` -- full administration (departments, tags, settings)
- **API routes** at `/support/api/v1/*` -- JSON API (when `api_enabled: true`)

The API's auth, guest-ticket, knowledge-base, department and tag endpoints are
public. Its ticket endpoints (`/support/api/v1/tickets/*`) are for agents. The
caller is the `current_user` your pipeline assigns or, failing that, the user
your `:api_token_validator` callback returns for an `Authorization: Bearer
<token>` header, and must pass `:agent_check`. A request with neither is
answered 401; a user who is not an agent, 403.

```elixir
config :escalated,
  api_token_validator: &MyApp.Api.validate_token/1, # {:ok, user} | :error
  agent_check: &MyApp.Accounts.agent?/1
```

## Public request limits

Guest ticket creation, token lookup and guest ratings share a default budget of
20 requests per minute per remote IP. Widget and chat routes share a separate
20-request budget. An open guest chat polls every three seconds, so its message
polling, sending and typing routes have their own budget instead: 90 requests per
minute per chat capability and network, and 300 per network across all chat
capabilities, so changing guessed tokens cannot mint fresh budgets. IPv6 clients
are counted per /64. Limits run before controller work and return HTTP 429 with
`Retry-After` and `Cache-Control: no-store` when exhausted.

```elixir
config :escalated,
  guest_rate_limit: %{max_requests: 20, window_ms: 60_000},
  widget_rate_limit: %{max_requests: 20, window_ms: 60_000},
  widget_chat_rate_limit: %{max_requests: 90, max_requests_per_ip: 300, window_ms: 60_000}
```

The built-in fixed-window limiter is supervised by the Escalated OTP application,
serializes concurrent admission, expires idle counters, and caps storage at
50,000 IP/bucket entries. Limits are **per node** and reset when its process or
application restarts. A full store, unavailable backend or invalid configuration
returns HTTP 503 instead of allowing uncounted requests.

Multi-node hosts can configure `rate_limit_backend: MyApp.SharedRateLimiter`.
Its `check(bucket, key, max_requests, window_ms)` callback must atomically
return `:allow`, `{:deny, positive_retry_after_ms}`, or `{:error, reason}`. The
buckets `:guest`, `:widget` and `:widget_chat_network` key on the client's IP
tuple (an IPv6 address with its last 64 bits zeroed); `:widget_chat` keys on
`{ip_tuple, capability_hash}`, a hash of the chat capability, never the token.
Only a host's trusted-proxy pipeline should rewrite `conn.remote_ip`; Escalated
does not trust `X-Forwarded-For` itself. Edge rate limits remain useful for
distributed traffic. Guest email proof also has a database-backed mailbox budget
shared across tenants and nodes. Setup and request shapes are documented in
[merchant and guest integration](docs/merchant-and-guest-access.md).

## Inbound email

Point your Postmark, Mailgun, or AWS SES (via SNS HTTP subscription) inbound webhook at:

```
POST /support/webhook/email/inbound?adapter=postmark
POST /support/webhook/email/inbound?adapter=mailgun
POST /support/webhook/email/inbound?adapter=ses
```

The adapter can be selected via the query parameter or the `x-escalated-adapter` header. Your provider must attach the shared secret as `x-escalated-inbound-secret`, which is compared with `Plug.Crypto.secure_compare/2` (timing-safe).

Configure the symmetric secret + mail domain (used for signed `Reply-To` + canonical `Message-ID` headers) in `config/runtime.exs`:

```elixir
config :escalated,
  mail_domain: System.get_env("ESCALATED_MAIL_DOMAIN", "support.yourapp.com"),
  email_inbound_secret: System.fetch_env!("ESCALATED_INBOUND_SECRET"),
  inbound_parsers: [
    Escalated.Services.Email.Inbound.PostmarkParser,
    Escalated.Services.Email.Inbound.MailgunParser,
    Escalated.Services.Email.Inbound.SESParser
  ]
```

Register the controller route:

```elixir
scope "/support/webhook/email", Escalated.Controllers do
  pipe_through :api
  post "/inbound", InboundEmailController, :inbound
end
```

Outbound notifications carry a signed `Reply-To` (`reply+{id}.{hmac8}@{mail_domain}`). Because the controller requires `email_inbound_secret`, only that signed address links an inbound message to a ticket; `Message-ID` headers and subject-reference tags are guessable and are used only by hosts that call `Escalated.Services.Email.Inbound.Service` directly without a secret.

A linked message becomes a reply only when its `From` address (case-insensitive) is the ticket's requester: the guest email, the requester's Contact email, or the requester user's email. It is posted as that requester, and only such a reply reopens a resolved or closed ticket. Staff identity is never taken from `From`, so agents reply in the app; mail from anyone else, an agent's address included, opens a new ticket instead of being dropped. Lookups use `Escalated.repo/0`, so with tenancy enabled they stay inside the tenant resolved for the webhook request. Have your provider enforce SPF/DKIM/DMARC as well, since `From` itself is unauthenticated.

Unmatched messages with real content create a new ticket; SNS subscription confirmations and empty body+subject messages are skipped.

See the [inbound email docs](https://docs.escalated.dev/inbound-email) for provider setup, the response shape, and a ready-to-paste curl test recipe.

## Custom Ticket Actions

Host applications can add custom buttons to the agent ticket screen and react to
clicks by subscribing to the broadcast event. Register actions under the
`:custom_actions` config key:

```elixir
config :escalated,
  custom_actions: [
    %{
      key: "sync-crm",
      label: "Sync CRM",
      variant: "primary",
      confirmation: "Sync this ticket to the CRM?",
      metadata: %{icon: "refresh-cw"},
      # visible / enabled may be a boolean or fn(ticket, user) -> boolean
      enabled: fn ticket, _user -> ticket.status in ["open", "in_progress"] end
    }
  ]
```

Visible actions are exposed on the agent ticket show as `customActions` and on
the API ticket detail response as `custom_actions` (each with a `url` and
`method`). Triggering one (`POST /support/agent/tickets/:reference/actions/:action`
or the API equivalent) validates the action is visible (404) and enabled (403),
records an internal note for auditability, and broadcasts
`ticket:custom_action_triggered`:

```elixir
Escalated.Broadcasting.subscribe_ticket(ticket_id)

# In your LiveView / GenServer handle_info:
def handle_info(%{event: "ticket:custom_action_triggered", payload: payload}, socket) do
  # payload.action, payload.user_id, payload.payload, payload.metadata
  {:noreply, socket}
end
```

## Usage

### Creating Tickets Programmatically

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Replying to Tickets

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Assigning Tickets

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA Management

```elixir
# Check for SLA breaches (dispatches sla.breached) and deadlines due within
# 30 minutes (dispatches sla.warning). Run both periodically via a scheduler,
# or run `mix escalated.check_sla`, which does exactly this.
breached = Escalated.Services.SlaService.check_breaches()
warned = Escalated.Services.SlaService.check_warnings(30)

# Get SLA statistics
stats = Escalated.Services.SlaService.stats()
```

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

## Newsletters (optional, partial port)

Schema, schemas, and renderer for the admin-only newsletter broadcast feature. Off by default — host integrators flip `:newsletter_tracking_enabled` and other application env values to configure behavior. The DB-bound planner / dispatcher / tracker services need integration with the host's Repo layer and ship as a follow-up.

```elixir
# config/config.exs
config :escalated,
  app_url: "https://support.example.com",
  newsletter_default_theme: "default",
  newsletter_tracking_enabled: true,
  newsletter_brand_accent: "#2563eb",
  newsletter_brand_physical_address: "Acme Inc. · 123 Main St",
  newsletter_markdown_renderer: &Earmark.as_html!/1
```

```elixir
alias Escalated.Services.Newsletter.Renderer

html = Renderer.render(delivery, newsletter, contact, template_or_nil)
```

The package ships:
- `priv/repo/migrations/20260522000001_create_newsletter_system.exs` — Ecto migration
- `lib/escalated/schemas/newsletter/*.ex` — 5 Ecto schemas
- `lib/escalated/services/newsletter/renderer.ex` — full renderer
- `priv/templates/newsletter_themes/{default,branded}.html.eex` — starter themes

Follow-up PR: planner / dispatcher / tracker services using the host's Repo, plus router controllers.

## Translations

Escalated for Phoenix consumes its translation catalogs from the central
[`:escalated_locale`](https://hex.pm/packages/escalated_locale) Hex package
so that every Escalated host plugin (Phoenix, Laravel, Rails, Django, …)
ships an identical message set.

The central package exposes Gettext-style `.po` files at
`priv/gettext/{locale}/LC_MESSAGES/escalated.po`. This repository defines an
`Escalated.Gettext` backend that re-exports those catalogs and additionally
loads any per-host overrides placed under
`priv/gettext/overrides/{locale}/LC_MESSAGES/escalated.po`.

Override pattern:

```
priv/gettext/overrides/
└── en/
    └── LC_MESSAGES/
        └── escalated.po   # only the strings you want to differ from upstream
```

Translation contributions should be opened against
[`escalated-dev/escalated-locale`](https://github.com/escalated-dev/escalated-locale),
not this repository — that way every host plugin picks the change up on the
next `mix deps.update escalated_locale`.

## License

MIT License. See [LICENSE](LICENSE) for details.
