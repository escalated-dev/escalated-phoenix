# Embedding the widget on other sites

The support widget, ticket form and live chat can run on a site other than
the one Escalated is installed on: a store, a marketing site or a customer
portal loads one script from your Escalated install. Nothing changes until you
list the sites that may do this.

## 1. Allow the embedding sites

Either in your config (a list, or one comma separated string, which suits an
environment variable):

```elixir
# config/runtime.exs
config :escalated,
  widget_allowed_origins: System.get_env("ESCALATED_WIDGET_ALLOWED_ORIGINS", "")
```

```dotenv
ESCALATED_WIDGET_ALLOWED_ORIGINS=https://shop.example.com,https://*.example.org
```

or in **Admin > Settings > Support Widget > Sites that can embed the widget**
(one per line). Both lists are combined. Each entry is an origin:
`scheme://host[:port]` over http or https, no path, query or user name.
`https://*.example.org` matches every subdomain of `example.org` but not
`example.org` itself. A bare `*` is rejected, and the admin form refuses any
entry that is not an origin.

The admin field is stored per tenant when tenancy is on; the config list
applies to every tenant. The admin page shows the field while the widget is
enabled (`config :escalated, widget_settings: %{enabled: true}`, the default).

## 2. Mount the widget routes in a pipeline of their own

The widget's POSTs from another site carry no session cookie and so no CSRF
token. `Escalated.Plugs.WidgetCors` marks requests from listed sites so
`Plug.CSRFProtection` skips them, which only works when it runs **before**
`:protect_from_forgery`. The widget is also public, so it must not sit behind
your sign-in requirement. Mount it separately:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use Escalated.Router

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

`escalated_widget_routes/1` mounts `{prefix}/widget/*`, including `embed.js`;
`widget: false` stops `escalated_routes/2` from mounting the same routes
again. Hosts that keep calling `escalated_routes/2` alone still get CORS
headers and preflight answers (the package runs `WidgetCors` at the start of
its widget scope), but a cross-site POST then fails the host's CSRF check, and
any sign-in requirement in the host pipeline applies to the widget too.

## 3. Add the script to the other site

```html
<script src="https://help.example.com/support/widget/embed.js" async></script>
```

For an on-page support form instead of a floating button:

```html
<div id="support-form"></div>
<script
    src="https://help.example.com/support/widget/embed.js"
    data-mode="inline"
    data-target="#support-form"
    data-tabs="ticket"
    data-meta-order-number="A-1001"
></script>
```

All host parameters (tabs, department, prefill, metadata, title, the
JavaScript API) are described in the frontend package's
[embedding guide](https://github.com/escalated-dev/escalated/blob/main/docs/embedding-the-widget.md).

## What the server does

For a request whose `Origin` is on the list, the widget routes:

- answer preflight requests (`OPTIONS` with `Access-Control-Request-Method`)
  with 204, `Access-Control-Allow-Origin: <origin>`, methods
  `GET, POST, OPTIONS`, headers
  `Accept, Authorization, Content-Type, X-Requested-With` and a 600-second
  `Access-Control-Max-Age`;
- add `Access-Control-Allow-Origin`, `Access-Control-Expose-Headers:
  Retry-After` and `Vary: Origin` to every response, including validation
  errors (422), unknown tickets (404) and rate-limit answers (429). Credentials
  are never allowed;
- set `:plug_skip_csrf_protection`, so `:protect_from_forgery` lets the request
  through;
- treat the visitor as a guest even if the same browser is signed in to your
  app: `:current_user` is cleared (again after your later pipeline plugs, at
  the start of the package's widget scope) and the session is not written
  back. Guest access tokens (`Authorization: Bearer`, `X-Guest-Token`) work as
  before.

Requests from any other origin, and same-origin requests, are handled exactly
as before, including the CSRF check. Their preflights get a 204 without any
CORS grant. Guest email verification, rate limits and the widget's `enabled`
switch apply to embedded requests unchanged.

With tenancy on, `WidgetCors` runs before `Escalated.Plugs.ResolveTenant`. It
resolves the tenant through your `tenant_resolver` to read the admin list; if
that is not possible yet, only the config list is consulted.

### Host parameters

`GET {prefix}/widget/config` returns `accepts_metadata: true`. Widget tickets
(`POST {prefix}/widget/tickets`) store the `metadata` object the page sends in
the ticket's `metadata`, next to the server's own `source: "widget"`; live
chats (`POST {prefix}/widget/chat/start`) store it in the chat ticket's
`metadata`. The values come from the visitor's browser, so only a flat map is
kept: up to 25 entries (in key order), keys of letters, digits, `_ . : -` (64
characters at most), and string, number or boolean values (strings trimmed and
cut to 500 characters). `page_url` is kept only when it is an http(s) URL of
at most 2048 bytes. `embedded_on` is always set by the server from the
request's `Origin` and cannot be supplied by the page. A `metadata` value that
is not an object, or has more than 50 keys, is answered 422. Treat all of it as
unverified visitor input.

### What the widget reads

These widget routes answer in the shape the shared widget
(`@escalated-dev/escalated` 0.12) expects, embedded or on your own pages:

- `GET {prefix}/widget/config` returns, at the top level, `color` (from
  `widget_settings.primary_color`, which is still returned), `position`
  (`widget_settings.position`, default `"bottom-right"`), `greeting`,
  `departments` (the active departments, as `[%{id, name}]`), `kb_enabled`,
  `guest_tickets_enabled`, `accepts_metadata`, `guest_verification_required`
  and `status_lookup_enabled` (both `true`). The same map is also under
  `widget`.
- `GET {prefix}/widget/articles?q=` searches published knowledge-base
  articles (`q` of 2 to 200 characters, else 422) and returns up to ten as
  `%{articles: [%{title, slug, excerpt}]}`. `GET {prefix}/widget/articles/:slug`
  returns one published article as `%{title, slug, body, category}` and counts
  the view. Both follow the knowledge base's settings: 404 while
  `knowledge_base_enabled` is off, 403 for a visitor who is not signed in while
  `knowledge_base_public` is off (embedded visitors are never signed in).
  `kb_enabled` in `/config` is `true` only when the articles can be read.
- `POST {prefix}/widget/tickets` and `POST {prefix}/widget/chat/start` accept
  `department_id` (a number or a numeric string). A value that names no active
  department is ignored and the ticket is filed without one. The ticket answer
  carries `message` and `reference` at the top level.
- `GET {prefix}/widget/chat/:id/messages` gives each message `is_agent` and
  `author: %{name}`: the agent's `AgentProfile` display name (or the `name` of
  your `user_schema` record), `"Support"` when there is neither, and the
  guest's name for the guest's own messages. `agent` names the agent who
  joined the chat.
- The verified status view, `GET {prefix}/widget/tickets/:reference` with the
  guest's bearer token, adds `status_label`, `status_color` and `department`,
  and gives each reply `author` (a name, as above) and `is_agent`. Status is
  only shown after the visitor proves the mailbox through
  `POST {prefix}/widget/verification` and `POST {prefix}/widget/lookup`;
  nothing is shown for an email address alone.

### The script

`GET {prefix}/widget/embed.js` serves `priv/static/widget/escalated-widget.js`,
the standalone bundle from `@escalated-dev/escalated` 0.12.1, with
`Content-Type: application/javascript; charset=utf-8`, a one-hour cache, an
ETag (304 on a matching `If-None-Match`), `X-Content-Type-Options: nosniff`,
`Cross-Origin-Resource-Policy: cross-origin` and
`Access-Control-Allow-Origin: *`.

## Configuration

```elixir
config :escalated,
  # list or comma separated string
  widget_allowed_origins: ["https://shop.example.com", "https://*.example.org"],
  # seconds browsers may cache a preflight
  widget_preflight_max_age: 600
```

## Troubleshooting

- **The browser reports a CORS error.** The page's origin is not on the list,
  or it differs in scheme or port (`http://` vs `https://`, `:8080`).
- **Requests raise `Plug.CSRFProtection.InvalidCSRFTokenError` (403).** The
  origin was not recognised, or `Escalated.Plugs.WidgetCors` runs after
  `:protect_from_forgery`. Mount the widget routes as in step 2.
- **Requests redirect to your sign-in page.** The widget routes are mounted
  behind your authentication pipeline. Mount them as in step 2.
- **A host-wide CORS plug (such as `Corsica` or `CORSPlug`).** It is not needed
  for the widget routes. If it covers `/support/widget/*`, it may answer the
  preflights first with its own settings.
