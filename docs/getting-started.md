# Getting started

## Installation

Requires Elixir 1.15+ and Ecto SQL 3.14+ on the 3.x line. The package requires Decimal 3.1.2+
within the 3.x line to exclude CVE-2026-97853; earlier Ecto lines depend on
Decimal versions that do not contain that fix. Existing hosts should update
their Ecto and Decimal dependencies together and run `mix hex.audit`.

Add `escalated` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:escalated, "~> 0.2.14", hex: :escalated_phoenix}
  ]
end
```

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
[upgrade guide](merchant-and-guest-access.md#provisioning-and-upgrading)
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

  # The public support widget gets a pipeline of its own: no sign-in
  # requirement, and WidgetCors before the CSRF check so sites listed in
  # `widget_allowed_origins` can embed it.
  pipeline :escalated_widget do
    plug :accepts, ["json"]
    plug :fetch_session
    plug Escalated.Plugs.WidgetCors
    plug :protect_from_forgery
  end

  scope "/" do
    pipe_through :escalated_widget
    escalated_widget_routes("/support")
  end

  scope "/" do
    pipe_through [:browser, :authenticated]
    escalated_routes("/support", widget: false)
  end
end
```

Single sign-on, when you switch it on, needs its routes outside your sign-in
pipeline too: mount `escalated_sso_routes("/support")` in a pipeline with a
session but without `:protect_from_forgery`, and pass `sso: false` to
`escalated_routes/2` (see [access control](access-control.md#mounting-the-routes)).

Existing routers that call `escalated_routes("/support")` alone keep working
unchanged: it still mounts the widget routes, inside your pipeline. Split them
out as above to embed the widget on other sites; see
[embedding the widget](embedding-the-widget.md).

This mounts:

- **Customer routes** at `/support/tickets/*` -- view/create/reply to the signed-in user's own tickets. Creation accepts subject, description, priority, ticket type and department; requester identity and staff-controlled fields come from the server. CSAT by reference requires the authenticated requester. API reply authors are taken from the authenticated agent.
- **Agent routes** at `/support/agent/*` -- agent dashboard and ticket management
- **Admin routes** at `/support/admin/*` -- full administration (departments, tags, settings)
- **API routes** at `/support/api/v1/*` -- JSON API (when `api_enabled: true`), including the mobile guest API at `/support/api/v1/mobile/guest/*` (see [verified guest access](merchant-and-guest-access.md#mobile-guest-api))
- **Widget routes** at `/support/widget/*` -- the public support widget and its `embed.js` (unless `widget: false`)

The API's auth, guest-ticket, knowledge-base, department and tag endpoints are
public. Its ticket endpoints (`/support/api/v1/tickets/*`) are for agents. The
caller is the `current_user` your pipeline assigns or, failing that, the user
your `:api_token_validator` callback returns for an `Authorization: Bearer
<token>` header, and must pass `:agent_check`. A request with neither is
answered 401; a user who is not an agent, 403. Admins can also issue API
tokens from the admin panel; see [API tokens](api-tokens.md).

```elixir
config :escalated,
  api_token_validator: &MyApp.Api.validate_token/1, # {:ok, user} | :error
  agent_check: &MyApp.Accounts.agent?/1
```

## Required: schedule the recurring jobs

SLA breach checks, escalation rules, automations, delayed workflow actions and
snooze wake-ups run only when something runs them on a timer. Nothing in a
Phoenix app does that by default, so pick one of these:

**In-process (simplest).** Add `Escalated.Scheduler` to your supervision tree
after your repo. It runs every job below at its interval, one run of a job at a
time, for every tenant in your trusted catalog when tenancy is on:

```elixir
children = [
  MyApp.Repo,
  Escalated.Scheduler,
  MyAppWeb.Endpoint
]
```

On a cluster, start it on one node only, or every node runs every job.

**Your own scheduler.** Run each job at its interval: `mix escalated.<job>` from
cron, or `Escalated.Scheduler.run(:job)` from Oban or Quantum (use this in a
release, where Mix tasks are not available).

| Job | Mix task | Interval |
|-----|----------|----------|
| `:check_sla` | `mix escalated.check_sla` | every minute |
| `:run_due_delayed_actions` | `mix escalated.run_due_delayed_actions` | every minute |
| `:wake_snoozed_tickets` | `mix escalated.wake_snoozed_tickets` | every minute |
| `:evaluate_escalations` | `mix escalated.evaluate_escalations` | every 5 minutes |
| `:run_automations` | `mix escalated.run_automations` | every 5 minutes |

Optional features add their own: `mix escalated.newsletters.dispatch` (every
minute, with newsletters on), `mix escalated.purge_guest_access` (hourly, with
guest access; see [merchant and guest access](merchant-and-guest-access.md))
and `mix escalated.purge_expired` (daily, with data retention).

Every SLA check records a heartbeat. When it is missing or more than 15
minutes old, the admin Settings page and the Reports overview and dashboard
warn that the recurring jobs are not running and list what to schedule (their
`scheduler` prop: `healthy`, `last_run_at`, `message`, `commands`), and
`mix escalated.doctor` reports it.

## Check the setup

`mix escalated.doctor` reports a user schema that does not meet
`Escalated.UserContract` (unset, not an Ecto schema, or without `:id`), staff
gates that are missing (no `agent_check` / `admin_check` and no `is_agent` /
`is_admin` fields), and the recurring jobs' heartbeat. It exits non-zero on an
error. In a release, call `Escalated.UserContract.problems/0` and
`Escalated.Scheduler.status/0`.

## Optional public routes and staff-only installs

The widget and the guest portal are public: they answer requests from people
who are not signed in. On an install that does not use them, switch their
routes off so they are not mounted at all. A customer route, by default,
accepts any signed-in user; `customer_middleware` adds your own guard to them.
All three are read when your router compiles (put them in `config/config.exs`,
not `runtime.exs`, and recompile after a change):

```elixir
config :escalated,
  routes: [
    # No /support/widget/* route, from escalated_routes/2 or
    # escalated_widget_routes/1. Default true; env ESCALATED_WIDGET_ENABLED.
    widget: false,
    # No /support/guest/*, /support/api/v1/guest/* or
    # /support/api/v1/mobile/guest/* route. Default true;
    # env ESCALATED_GUEST_ROUTES.
    guest: false,
    # Plugs (or pipeline names) run after the customer plugs on the customer
    # ticket routes (/support/tickets/*, including CSAT by reference) and the
    # customer knowledge base (/support/kb/*). Default [].
    customer_middleware: [Escalated.Plugs.EnsureAgent]
  ]
```

Together these make the portal **staff-only**: no public widget or guest
routes, and a signed-in user who is not an agent gets 403 from the customer
and knowledge-base routes instead of being able to list and raise tickets. Use
any plug of your own in place of `Escalated.Plugs.EnsureAgent`.

The runtime switches keep working inside routes that are mounted:
`widget_settings: %{enabled: false}` still refuses widget requests, and the
knowledge base settings still answer 404. `escalated_routes/2` also takes
`guest: false`, like `widget: false` and `sso: false`.

Slack and a cloud-to-site webhook are not part of this package, so there are
no routes of theirs to switch off.

## Embedding the admin in your own admin panel (optional)

The admin at `/support/admin` is the default and needs nothing more. If your
app already has an admin panel, you can show Escalated's admin screens inside
it instead: under your URL prefix and pipelines, inside your Vue layout or your
HEEx admin root layout, or in an iframe on another origin you allow. Nothing
changes until you turn it on:

```elixir
# config/config.exs (read when your router compiles)
config :escalated, :ui,
  embed: [
    enabled: true,
    prefix: "/admin/support",
    middleware: [:require_admin],
    layout: "Layouts/AdminLayout"
  ]
```

Your `escalated_routes/2` call then mounts the admin under `/admin/support`
(same controllers and route names; `/support/admin` is no longer routed),
Escalated's admin gate stays on unless you set `replace_admin_gate: true`, and
every Inertia page carries `escalated.embed` and the admin menu as
`escalated.navigation` (`Escalated.admin_navigation/2` returns it for HEEx).
The agent panel, customer portal, widget, API, two-factor and newsletter URLs
do not move. See [embedding the admin](embedding-admin.md) for the three
setups (Vue + Inertia, HEEx root layout, iframe), every key and the security
notes.
