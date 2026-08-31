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

## Installation

Add `escalated` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Configuration

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
| `repo` | *required* | Your Ecto Repo module |
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

Run the Escalated migration:

```bash
mix ecto.gen.migration create_escalated_tables
```

Then copy the migration content from `priv/repo/migrations/20260406000001_create_escalated_tables.exs` or install via:

```bash
mix ecto.migrate
```

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

- **Customer routes** at `/support/tickets/*` -- view/create/reply to tickets
- **Agent routes** at `/support/agent/*` -- agent dashboard and ticket management
- **Admin routes** at `/support/admin/*` -- full administration (departments, tags, settings)
- **API routes** at `/support/api/v1/*` -- JSON API (when `api_enabled: true`)

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

The service resolves inbound messages to existing tickets via, in order: canonical `Message-ID` headers, signed `Reply-To` verification, and subject-reference tags. Unmatched messages with real content create a new ticket; SNS subscription confirmations and empty body+subject messages are skipped.

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
# Check for SLA breaches (run periodically via a scheduler)
breached = Escalated.Services.SlaService.check_breaches()

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
