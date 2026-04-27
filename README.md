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
| `ui_enabled` | `true` | Mount Inertia.js UI routes |
| `api_enabled` | `false` | Mount JSON API routes |
| `admin_check` | `nil` | Function `(user -> boolean)` for admin access |
| `agent_check` | `nil` | Function `(user -> boolean)` for agent access |
| `default_priority` | `:medium` | Default ticket priority |
| `allow_customer_close` | `true` | Allow customers to close their tickets |
| `sla` | `%{enabled: true, ...}` | SLA configuration map |

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

By default, Escalated renders pages via [Inertia.js](https://github.com/inertiajs/inertia-phoenix) when `inertia_phoenix` is installed. If Inertia is not available, controllers fall back to JSON responses.

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

## License

MIT License. See [LICENSE](LICENSE) for details.
