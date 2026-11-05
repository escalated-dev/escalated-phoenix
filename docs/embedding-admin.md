# Embedding the admin in your own admin panel (optional)

Escalated ships a complete standalone admin at `/support/admin` (the prefix you
pass to `escalated_routes/2` + `/admin`), with its own sidebar and top bar.
**That is the default, and it needs no setup.** If your Phoenix app already has
an admin panel, you can instead show Escalated's admin screens inside it: under
your sidebar and header, your URL prefix and your pipelines.

This is an optional alternative to the standalone admin. Nothing on this page
has any effect until you turn it on: with no embed configuration every route,
page, prop, header and gate is exactly what it was before (a test compares the
whole route table with a snapshot taken before this feature existed). The
design is in the ADR
[`2026-11-05-embeddable-admin`](https://github.com/escalated-dev/escalated-developer-context/blob/main/decisions/2026-11-05-embeddable-admin.md);
the frontend side is documented in
[`@escalated-dev/escalated` docs/embedding-admin.md](https://github.com/escalated-dev/escalated/blob/main/docs/embedding-admin.md).

## Contents

- [Pick your setup](#pick-your-setup)
- [Turning it on](#turning-it-on)
- [Configuration reference](#configuration-reference)
- [What changes, and what does not](#what-changes-and-what-does-not)
- [1. Vue + Inertia host](#1-vue--inertia-host)
- [2. HEEx host](#2-heex-host)
- [3. iframe](#3-iframe)
- [The admin menu: `escalated.navigation`](#the-admin-menu-escalatednavigation)
- [Security](#security)
- [Turning it off](#turning-it-off)

## Pick your setup

| Your admin panel | Use | `mode` |
|---|---|---|
| Inertia + Vue in this app | [Vue + Inertia host](#1-vue--inertia-host) | `:layout` |
| HEEx templates (controllers or LiveView) | [HEEx host](#2-heex-host) (your admin root layout as `root_view`) | `:layout` |
| Another app or origin, a non-Vue SPA, a CMS admin | [iframe](#3-iframe) | `:iframe` |

## Turning it on

Set the keys under `config :escalated, :ui, embed:`. `enabled`, `prefix`,
`middleware` and `replace_admin_gate` decide which routes `escalated_routes/2`
mounts, so they are read **when your router compiles**: put them in
`config/config.exs` (or `config/prod.exs`), not `config/runtime.exs`. Elixir
refuses to boot a release whose runtime configuration changes them, rather than
serve a router that disagrees with it. Environment variables read there are read
at build time.

```elixir
# config/config.exs
config :escalated, :ui,
  embed: [
    enabled: System.get_env("ESCALATED_EMBED", "false") == "true",
    prefix: System.get_env("ESCALATED_EMBED_PREFIX", "/admin/support"),
    # Your own pipelines (or plug modules) for the admin routes, on top of the
    # pipelines of the scope you call escalated_routes/2 in.
    middleware: [:require_admin],
    replace_admin_gate: false,
    layout: "Layouts/AdminLayout",
    root_view: nil
  ]
```

`mode`, `layout`, `root_view` and `frame_ancestors` are read on each request, so
they may also come from `config/runtime.exs`:

```elixir
# config/runtime.exs
config :escalated, :ui,
  embed: [
    mode: System.get_env("ESCALATED_EMBED_MODE", "layout"),
    frame_ancestors: System.get_env("ESCALATED_EMBED_FRAME_ANCESTORS", "")
  ]
```

(Config files merge keyword lists, so the two blocks combine. String values are
accepted as they come from the environment: `"true"`, `"iframe"`, and a
comma-separated origin list.)

Your router does not change: the `escalated_routes/2` call you already have
mounts the admin under `prefix` while `enabled` is true. Call it from a scope
at `/` (as the README's router setup does), so `prefix` is the URL the admin
answers at. Recompile after changing the compile-time keys
(`mix compile --force` if Mix does not pick the change up).

## Configuration reference

| Key (`config :escalated, :ui, embed:`) | Env var (read in your config) | Default | Read | Meaning |
|---|---|---|---|---|
| `enabled` | `ESCALATED_EMBED` | `false` | compile time | Master switch. While `false`, nothing below has any effect. |
| `mode` | `ESCALATED_EMBED_MODE` | `:layout` | per request | `:layout` (Vue + Inertia or HEEx host) or `:iframe`. |
| `prefix` | `ESCALATED_EMBED_PREFIX` | `"admin/support"` | compile time | URL prefix the admin moves under. Slashes around it are optional. |
| `middleware` | | `nil` | compile time | Pipeline names (`:require_admin`) or plug modules piped through on the admin routes. `nil` adds none: the admin runs with the pipelines of the scope `escalated_routes/2` is in, as the standalone admin does. |
| `replace_admin_gate` | | `false` | compile time | `true` removes Escalated's admin gate (`Escalated.Plugs.EnsureAdmin`) from these routes so your middleware alone decides. See [Security](#security). |
| `layout` | | `nil` | per request | Name of your Vue admin layout, matched against the frontend plugin's `layouts` option. |
| `root_view` | | `nil` | per request | Root layout `{module, template}` for embedded pages ([HEEx host](#2-heex-host)). |
| `frame_ancestors` | `ESCALATED_EMBED_FRAME_ANCESTORS` (comma-separated) | `[]` | per request | iframe mode: exact origins allowed to frame the admin. Wildcards, `*`, paths and non-http(s) values are ignored. |

Phoenix has no service-provider call to set these from code; the configuration
is the switch. `Escalated.Embed` reads it (`Escalated.Embed.enabled?/0`,
`base_url/0`, ...).

## What changes, and what does not

While embedding is on:

- Every admin route that lived under `/support/admin` (the admin screens,
  plugin pages, API tokens, import, reports) is mounted under your `prefix`
  instead, with the same controllers, actions and route helper names. Each runs
  `Escalated.Plugs.ApplyEmbedContext`, the shared error page, your
  `middleware`, tenancy and ticket visibility, then Escalated's own guards
  (`EnsureAdmin` unless you replace it, `RequireTwoFactor`,
  `EnforceRoutePermissions`). The old `/support/admin/...` URLs are not routed
  (404).
- The named routes the shared pages call (`route('escalated.admin.…')`, the
  `ziggy` prop, `Escalated.Routes`) follow the move, and so do the admin's
  redirects and pagination links.
- Every Inertia page carries `escalated.embed` and `escalated.navigation` (from
  `Escalated.Plugs.ShareInertiaData`).

Unchanged: the agent panel (`/support/agent`), customer portal, guest pages,
knowledge base, widget, API, single sign-on, the two-factor enrolment page
(`/support/admin/settings/two-factor`) and challenge, and the newsletter admin
(`/support/admin/newsletters`).

`escalated.embed` on an embedded page:

```json
{
  "enabled": true,
  "mode": "layout",
  "layout": "Layouts/AdminLayout",
  "route": "escalated.admin.tickets.index",
  "base_url": "/admin/support",
  "allowed_origins": []
}
```

On every other page `enabled` is `false` and `route` is `null`. Phoenix routes
have no names, so `route` is the shared frontend's name for the page (the
`Escalated.Routes` entry whose path and method match the request).

## 1. Vue + Inertia host

Backend: turn embedding on (above) with your prefix and admin pipeline.

Frontend (`assets/js/app.js`): register your admin layout under the name you
gave `layout`:

```js
import { createApp, h } from 'vue';
import { createInertiaApp } from '@inertiajs/vue3';
import { EscalatedPlugin, resolveEscalatedPage } from '@escalated-dev/escalated';
import AdminLayout from './layouts/AdminLayout.vue';
import AppLayout from './layouts/AppLayout.vue';

createInertiaApp({
    resolve: (name) => resolveEscalatedPage(name, async () => {
        const pages = import.meta.glob('./pages/**/*.vue');
        return (await pages[`./pages/${name}.vue`]()).default;
    }),
    setup({ el, App, props, plugin }) {
        createApp({ render: () => h(App, props) })
            .use(plugin)
            .use(EscalatedPlugin, {
                layout: AppLayout, // customer pages, as before
                layouts: { 'Layouts/AdminLayout': AdminLayout }, // embedded admin pages
                theme: { panel: { mode: 'light' } }, // match your admin
            })
            .mount(el);
    },
});
```

Your admin layout needs the same slots the plugin's `layout` always required, a
`#header` slot (Escalated puts the page title there) and a default slot. List
Escalated's menu with `<EscalatedNavigation />`:

```vue
<!-- assets/js/layouts/AdminLayout.vue -->
<script setup>
import { Link } from '@inertiajs/vue3';
import { EscalatedNavigation } from '@escalated-dev/escalated';
</script>

<template>
    <div class="flex min-h-screen">
        <aside class="w-64 border-r bg-white p-3">
            <Link href="/admin">Dashboard</Link>
            <!-- …your own items… -->
            <p class="mt-4 px-3 text-xs font-semibold uppercase text-gray-500">Support</p>
            <EscalatedNavigation />
        </aside>
        <div class="flex-1">
            <header class="border-b bg-white px-6 py-4"><slot name="header" /></header>
            <main class="p-6"><slot /></main>
        </div>
    </div>
</template>
```

Escalated renders each admin page chrome-free (no Escalated sidebar, top bar,
logo or footer) inside your layout. To use the same layout for customer pages
too, use `layout: AdminLayout, layoutScope: ['customer', 'admin']` instead of
`layouts`.

## 2. HEEx host

If your admin layout is a HEEx template, give embedded pages a root layout
that contains your chrome and the page, and point `root_view` at it:

```elixir
config :escalated, :ui,
  embed: [
    enabled: true,
    prefix: "/admin/support",
    middleware: [:require_admin],
    root_view: {MyAppWeb.Layouts, :escalated_admin}
  ]
```

```elixir
# lib/my_app_web/components/layouts.ex
def escalated_admin(assigns) do
  ~H"""
  <!DOCTYPE html>
  <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <meta name="csrf-token" content={get_csrf_token()} />
      <.inertia_title>Host admin</.inertia_title>
      <.inertia_head content={@inertia_head} />
      <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
      <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
      </script>
    </head>
    <body>
      <header id="host-admin-header">Host admin</header>
      <div class="flex">
        <aside id="host-admin-menu">
          <p class="menu-heading">Support</p>
          <ul>
            <li :for={item <- Escalated.admin_navigation(@conn.assigns[:current_user], @conn)}>
              <a
                href={item.url}
                class={if item.active, do: "active"}
                aria-current={if item.active, do: "page"}
              >
                {item.label}
              </a>
            </li>
          </ul>
        </aside>
        <main id="host-admin-main">{@inner_content}</main>
      </div>
      {Escalated.Routes.helper_tag(nonce: assigns[:csp_nonce])}
    </body>
  </html>
  """
end
```

(The test suite renders this template, without the asset and Inertia head
tags, in `test/support/embed_host.ex`.) Only embedded admin responses use this
root layout; every other page keeps the one your pipeline sets. Your Inertia
entry needs no extra option: Escalated sees `escalated.embed.enabled` and
renders the page chrome-free (title + content).

## 3. iframe

For an admin that is not part of this app (another origin, another stack),
frame the embedded admin:

```elixir
config :escalated, :ui,
  embed: [
    enabled: true,
    prefix: "/admin/support",
    mode: :iframe,
    frame_ancestors: ["https://admin.example.com"]
  ]
```

or `ESCALATED_EMBED=true`, `ESCALATED_EMBED_MODE=iframe`,
`ESCALATED_EMBED_FRAME_ANCESTORS=https://admin.example.com` read as shown in
[Turning it on](#turning-it-on).

Embedded responses then carry
`Content-Security-Policy: frame-ancestors 'self' https://admin.example.com` and
no `X-Frame-Options`. `ApplyEmbedContext` sets them with
`Plug.Conn.register_before_send/2` when the response is sent, after your
`middleware` and Escalated's controllers, so those cannot put the header back;
no other route is touched.

A CSP your app already sends is kept, and this directive is added as a second
policy. Browsers enforce both, so if your policy has its own `frame-ancestors`
it must list the same origins. Phoenix 1.8's `put_secure_browser_headers/2`
sends `frame-ancestors 'self'` by default: give it your origins in the pipeline
around `escalated_routes/2`:

```elixir
plug :put_secure_browser_headers, %{
  "content-security-policy" => "base-uri 'self'; frame-ancestors 'self' https://admin.example.com;"
}
```

On the framing page:

```html
<iframe id="support-admin" src="https://support.example.com/admin/support/tickets"
        style="width:100%;border:0" title="Support administration"></iframe>
<script type="module">
    import { connectEscalatedFrame } from '@escalated-dev/escalated/embed';

    const frame = connectEscalatedFrame(document.getElementById('support-admin'), {
        origin: 'https://support.example.com',
        onNavigate: ({ route, title }) => highlightMenu(route),
    });
    frame.setTheme('light');
</script>
```

The frame sizes itself to its content and reports each page change; the
protocol is in the frontend guide.

### Session cookies in a frame

- **Same site** (`admin.example.com` framing `support.example.com`): the default
  `same_site: "Lax"` session cookie works.
- **Cross-site** (different registrable domains): the session cookie must be
  sent in a third-party context. Set it in your endpoint's session options and
  serve both sites over HTTPS:

  ```elixir
  # lib/my_app_web/endpoint.ex
  @session_options [
    store: :cookie,
    key: "_my_app_key",
    signing_salt: "...",
    same_site: "None",
    secure: true
  ]
  ```

  Browsers that block third-party cookies will still not keep a session in a
  cross-site frame; use the Vue + Inertia or HEEx setup in that case.
- CSRF protection is unchanged.

## The admin menu: `escalated.navigation`

While embedding is on, every Inertia page shares the admin menu, and
`Escalated.admin_navigation(user, conn)` returns the same list (maps with atom
keys) for HEEx, whether or not embedding is on:

```json
[
  {
    "key": "tickets",
    "label": "Tickets",
    "route": "escalated.admin.tickets.index",
    "url": "/admin/support/tickets",
    "icon": "tickets",
    "position": 20,
    "active": true,
    "badge": null,
    "plugin": null,
    "children": []
  }
]
```

It is filtered for the user: empty for anyone who fails Escalated's admin gate
(unless you replaced it), Roles is left out while roles & permissions is off,
Newsletters is listed only while `enable_newsletters` is on (at its unchanged
`/support/admin/newsletters` URL), and while roles & permissions is on each
item needs the permission its screen requires (`Escalated.RoutePermissions`).
Active plugins' admin menu items are included (`key` `plugin:<slug>:<n>`,
`route` `null`), sorted by `position` with the core items. `route` is the
frontend's route name where it has one, else `null` (API tokens). Core `icon`
keys match the frontend's `escalatedNavIcons`.

## Security

- **The admin gate stays on by default.** Your `middleware` runs *in addition
  to* Escalated's `EnsureAdmin` (`:admin_check`). Set `replace_admin_gate` only
  if your middleware itself restricts the routes to admins: with it on, your
  middleware is the only check on who reaches the admin. Two-factor and route
  permissions still apply either way, and the agent panel keeps Escalated's
  gates.
- **Framing is allow-listed.** In iframe mode only the origins you list (plus
  your own) may frame the admin; nothing else, and never `*`.
- **No open `postMessage`.** The frame talks only to an allow-listed parent
  origin and ignores messages from anywhere else.

## Turning it off

Set `enabled: false` (or remove the `embed:` block) and recompile. The admin
returns to `/support/admin` with Escalated's own chrome.
