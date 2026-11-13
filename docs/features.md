# Features

## Features

Department visibility, account resolution and targeted SLAs are opt-in. See the
[ticket access and routing guide](ticket-access-and-routing.md) for configuration,
host integration hooks and migration instructions.

- **Ticket lifecycle** — Create, assign, reply, resolve, close, reopen with configurable status transitions
- **SLA engine** — Per-priority response and resolution targets, business hours calculation, automatic breach detection
- **Agent dashboard** — Ticket queue with filters, internal notes, canned responses
- **Customer portal** — Self-service ticket creation, replies, and status tracking
- **Admin panel** — Manage departments, SLA policies, tags, and view reports
- **Admin inside your own admin panel (optional)** — Off by default; the standalone admin stays the default. Turn it on to mount Escalated's admin under your prefix and pipelines, render it inside your Inertia layout or HEEx root layout (or an allow-listed iframe), and list its menu in your own sidebar ([guide](embedding-admin.md))
- **File attachments** — Drag-and-drop uploads with configurable storage and size limits
- **Activity timeline** — Full audit log of every action on every ticket
- **Department routing** — Organize agents into departments with auto-assignment
- **Tagging system** — Categorize tickets with colored tags
- **Ticket splitting** — Split a reply into a new standalone ticket while preserving the original context
- **Ticket snooze** — Snooze tickets with presets (1h, 4h, tomorrow, next week); `mix escalated.wake_snoozed_tickets` Mix task auto-wakes them on schedule
- **Saved views / custom queues** — Save, name, and share filter presets as reusable ticket views
- **Embeddable support widget** — Lightweight `<script>` widget with KB search, ticket form, and status check, served at `/support/widget/embed.js` and embeddable on other sites you list ([guide](embedding-the-widget.md))
- **Notification emails** — New ticket, reply, assignment, status, escalation and SLA breach emails sent through your Swoosh mailer once you set `mailer:` ([guide](notification-emails.md))
- **Email threading** — Outbound emails include proper `In-Reply-To` and `References` headers for correct threading in mail clients
- **Inbound email** — Single webhook endpoint with Postmark + Mailgun + AWS SES parsers, signed Reply-To verification, and Message-ID-based ticket resolution
- **Branded email templates** — Configurable logo, primary color, and footer text for all outbound emails
- **Real-time broadcasting** — Opt-in broadcasting via Phoenix PubSub with automatic polling fallback
- **Knowledge base toggle** — Enable or disable the public knowledge base from admin settings
- **Merchant tenancy** — Tenant-scoped data access, staff seats, jobs and realtime topics, with explicit legacy-data assignment
- **Verified guest access** — Email proof, expiring encrypted grants, private guest attachments and host-resolved tracking lookup
