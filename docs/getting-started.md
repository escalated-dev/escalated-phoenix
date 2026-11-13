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
