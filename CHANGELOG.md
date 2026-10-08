# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-10-08

### Upgrading

This release changes behaviour hosts rely on. Before deploying it:

- **Run every package migration**, including the three from September 30, 2026
  (`20260930000001_add_merchant_tenancy`, `20260930000002_add_verified_guest_access`
  and `20260930000003_clear_guest_challenge_results`, which clears guest proof
  results stored earlier):
  `mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations`.
  A host that copies package migrations must keep their version numbers. Take a
  backup first; the tenancy and guest-access migrations refuse some rollbacks.
- **Configure guest access before accepting public submissions.** Permanent guest
  tokens no longer grant access. Set `guest_access_secret` (at least 32 random
  bytes, stable across deploys) and a `guest_verification_delivery` callback.
- **Merchant tenancy is opt-in.** To use it, set `tenancy_enabled: true` and a
  `tenant_resolver` implementing `resolve/1`, `member?/2`, `reference?/3`,
  `scope_users/2`, `tenants/0` and `public_url/1`, plus `guest_reference_resolver`
  if guests look tickets up by your own references. Move an existing
  installation to a merchant with `mix escalated.backfill_tenant`. See
  [merchant and guest setup](docs/merchant-and-guest-access.md).
- **`Escalated.Tenancy.Maintenance.run` raises `Escalated.Tenancy.Maintenance.Error`**
  once the sweep finishes if any tenant failed (its `failures` field lists them).
  Schedulers that call it directly should expect the exception; mix tasks exit
  non-zero.
- **Inbound email:** only the ticket's requester can reply by email. Mail from
  anyone else, an agent's address included, opens a new ticket, so agents must
  reply in the app. With `email_inbound_secret` set, only the signed Reply-To
  address links mail to a ticket.
- **Staff callbacks:** `admin_check` and `agent_check` must return the boolean
  `true`. Any other value denies, with no fallback to stored roles.
- **Attachments:** downloads require the requester or an agent. With external
  storage, configure `:attachment_download_url` (otherwise downloads answer
  503) and make files that were publicly served private.
- **Guest rate limits:** guest ticket creation (5 per minute) and replies (10 per
  minute) are limited per client IP. Behind a proxy, rewrite `conn.remote_ip`
  from trusted proxies before the router, or every guest shares one limit.
- **Shared frontend:** ship a build of `@escalated-dev/escalated` that contains
  the settings page (escalated#185), tenant broadcasts (escalated#184) and guest
  forms (escalated#186, escalated#187).

### Added
- Guest ticket creation and replies are limited per client IP: 5 tickets and
  10 replies a minute, counted separately and before the guest token is
  resolved, so wrong-token guesses count. Configure with
  `guest_submission_rate_limit` (`enabled`, `tickets_per_minute`,
  `replies_per_minute`) (#138).
- The general settings page saves knowledge-base enablement, public access,
  feedback and footer branding. Invalid or unsupported input rejects the whole
  write with field errors (#128).
- Opt-in merchant tenancy with scoped repositories, tenant-local roles and unique
  keys, host membership and reference validation, isolated jobs and realtime
  channels, explicit provisioning and an offline legacy-data backfill command.
- Verified guest mailbox access for tickets, chat, tracking lookup and private
  attachments. Proof consumption is atomic with creation; capabilities expire,
  can be revoked and are bound to the merchant, mailbox and intended use.
- Shared mailbox delivery budgets, bounded proof attempts and scheduled cleanup
  of expired guest access records.

### Security
- Staff access is decided the same way for admin and agent routes, ticket APIs
  and realtime channels. `admin_check` and `agent_check` callbacks are
  authoritative and grant only on `true` (#129).
- Customer ticket creation uses the authenticated requester, satisfaction
  ratings by reference require that requester, and API replies are authored by
  the authenticated agent (#130).
- Attachment downloads check the requester or agent against the owning ticket
  and reply visibility; internal-note files are staff-only. External storage is
  served through a five-minute private URL from `:attachment_download_url` (#131).
- Public guest ticket creation, token lookup and guest rating routes enforce a
  per-IP budget. The limiter is supervised and admits concurrent requests
  atomically; over the limit it answers 429 with `Retry-After`, and 503 when its
  backend fails (#132).
- Customer ticket summaries distinguish contacts from host users with the same
  numeric ID and exclude internal-note timestamps and authors.
- Legacy permanent guest tokens no longer grant access. Hosts must configure
  verification delivery and a stable guest access secret before accepting public
  submissions. See [merchant and guest setup](docs/merchant-and-guest-access.md)
  for required migrations, callbacks and upgrade behavior.
- Guest proof rows no longer store issued capabilities; an identical retry
  re-derives an equivalent capability for the same grant. A migration clears
  results stored earlier.
- Mailbox code delivery is budgeted per mailbox and client network as well as
  per mailbox overall, so one network cannot exhaust an owner's budget. Public
  rate limits count IPv6 clients per /64.
- A disabled widget refuses verification, lookup, ticket and chat routes.
- Inbound email that threads onto a ticket becomes a reply only when it is sent
  by the ticket's requester (guest, contact or requester user email,
  case-insensitive), and it is posted as that requester. Other senders, agents'
  addresses included, open a new ticket and never reopen the matched one. With
  an inbound secret configured, only the signed Reply-To address links mail to
  a ticket. Accepted replies now reopen resolved and closed tickets.

### Fixed
- Guest chat polling, messages and typing have their own per-capability limit,
  so the widget's three-second polling no longer hits the general widget limit.
- Identical retries of a consumed guest proof no longer spend attempts.
- Concurrent first lookups of a ticket with no guest grant no longer fail with a
  unique-key error on MySQL.
- API guest ticket read/reply and guest ratings accept the capability headers.
- On PostgreSQL, creating a ticket outside a transaction (customer portal, API,
  inbound email, chat) no longer raises "transaction is not started".
- In merchant mode, rows that still name a user whose membership was revoked can
  be updated and deleted again; updates validate only the references they
  change. Maintenance tasks run every tenant even when one fails, then exit with
  an error listing the failed tenants.
- A reply, its activity entry and the ticket's first response time are saved in
  one transaction, and hooks run only after it commits.
- The scoped repo refuses query and placeholder values in `insert_all` rows.
- Disabled widget ticket and chat submissions now stop before creating tickets,
  contacts, activities or chat sessions. Database-backed regression tests cover
  both disabled paths and their enabled counterparts.

## [0.1.3] - 2026-09-13

### Fixed
- **Ticket creation could fail on a reference collision, losing the ticket.**
  The random part of a reference was six hex characters: 24 bits a month. A
  site creating about 10,000 tickets a month could expect several collisions a
  month. Each collision hit the unique index on `tickets.reference`, and the
  inbound email, widget, portal or chat ticket was lost with a changeset error.
  - **Format:** the random part is now 8 characters of Crockford base32 (40
    bits), leaving out the easily misread I, L, O and U. The format is still
    `ESC-YYMM-`, and existing references keep resolving.
  - **Retry:** an insert that hits the reference index is retried under a fresh
    reference, up to three attempts. This covers every path that inserts a
    ticket: `TicketService.create/1`, `split_ticket/3` and live chat. Other
    changeset errors are returned at once, as before.
  - **Test:** the 100-draw uniqueness test, which failed CI by chance, is
    replaced by deterministic format and encoding tests.

## [0.1.2] - 2026-09-13

### Security
- **Any signed-in user could follow any ticket in real time.** `TicketChannel`
  admitted any `current_user` to `escalated:ticket:<id>`, although its moduledoc
  promised only agents and the requester. It now checks the ticket's requester
  (#118).
- **Any customer could read and answer every customer's tickets.** The customer
  ticket list passed `requester_id` to `TicketService.list/1`, which ignored it,
  so it listed every ticket. The ticket page and reply found a ticket by
  reference or numeric id and never compared the requester. The list is now
  filtered to the signed-in user, and another user's ticket answers 403.
- **The JSON ticket API accepted anonymous requests.** `/api/v1/tickets/*` ran
  no pipeline, so anyone could list and read tickets and change their status,
  priority and assignee. Those routes now need a caller -- the host's
  `current_user`, or a bearer token the host's `:api_token_validator` accepts --
  who passes `:agent_check`: 401 without one, 403 for a non-agent. Integrations
  that called them anonymously must now send a token. The auth, guest-ticket,
  knowledge-base, department and tag endpoints are unchanged (#116).

### Fixed
- **Live chat and the admin snooze, unsnooze and split endpoints returned
  500.**
  - **Chat:** the eight agent and widget chat routes named fully qualified
    controllers inside scopes that already alias the namespace, so Phoenix
    prefixed it twice and routed to modules that don't exist. They are
    scope-relative now.
  - **Admin:** the admin routes pointed at actions only the agent controller
    has, and now delegate to them. `EnsureAdmin` still runs first.
  - **Test:** a new test walks the router and fails on any route whose
    controller or action doesn't exist (#117).
- **Browsers joined to a chat received nothing.** `ChatChannel` subscribes to
  `escalated:chat:<ticket_id>` and `escalated:chat:queue`, but chat events were
  only published to the ticket topics. `Broadcasting.broadcast_chat_event/2`
  publishes to the session topic and, for sessions starting, being taken and
  ending, to the queue topic as well (#118).
- **Nine of the seventeen webhook events offered in the admin were never
  sent.**
  - **Events:** `ticket.assigned`, `ticket.unassigned`, `ticket.escalated`,
    `ticket.department_changed`, `ticket.tag_added`, `ticket.tag_removed`,
    `ticket.updated`, `sla.breached` and `sla.warning` are now dispatched from
    the operations that cause them. `sla.breached` goes out only after the
    breach is saved.
  - **SLA warnings:** a new `SlaService.check_warnings/1` computes them.
  - **Scheduling:** `check_breaches/0` had no caller at all. The new
    `mix escalated.check_sla` task runs both; schedule it (#119).
- **Migrations could not run on MySQL.** Eight list columns used PostgreSQL
  arrays. On MySQL they are created as JSON, while PostgreSQL and SQLite keep
  exactly the columns they had, and the schemas are unchanged. Following a
  ticket and saving @mentions also failed on MySQL, because both inserts named
  a conflict target. CI gains a MySQL 8.4 job (#120).

## [0.1.1] - 2026-09-13

### Fixed
- **Fifteen screens rendered blank.** They rendered page names with no component
  behind them in `@escalated-dev/escalated`, and Inertia resolves such a name to
  nothing rather than to an error, so each returned 200 and an empty panel. Ten
  are renamed to the component the frontend ships: the agent and customer
  ticket screens, and the department, automation, escalation rule and workflow
  forms. The four ticket screens needed their props fixed as well: `TicketList`
  reads `tickets.data` and was handed a bare list, and the reply thread and
  activity feed read `ticket.replies` and `ticket.activities`, which arrived as
  sibling props.

  Tags, macros and canned responses are edited inline on their index screens
  and have no detail component, so their `show` actions now answer as API reads
  and `Tags#new` redirects to the index. `Admin/Settings/Index` stays blank: this
  package's settings are a different set of fields from the shared `Settings`
  screen, and pointing the name at it would render a form whose Save posts
  fields `update/2` ignores.

- **The shared workflow builder had no create, edit, toggle or reorder endpoint
  to talk to.** `GET /workflows/new` fell through to `show` and raised
  `Ecto.Query.CastError`, and the edit, toggle and reorder routes the Index page
  links to did not exist. A workflow with no actions could be saved, omitted
  conditions were stored as `{}`, a failed save answered an Inertia visit with a
  JSON 422, `{"any": []}` matched no ticket, and the form offered five triggers
  when only three are fired.

  The surface now follows escalated-developer-context
  `domain-model/workflow-admin-contract.md`. `new` and `edit` render the Form
  with `workflow`, `trigger_events`, `action_types` and `operators`;
  `POST /workflows/:id/toggle` and `POST /workflows/reorder` exist; and a
  workflow needs a name, a trigger and at least one action, with omitted
  conditions stored as `{"all": []}`. A failed Inertia save redirects back with
  its errors, while other callers keep the JSON 422, and `{"any": []}` matches
  every ticket. Phoenix has no Ziggy, so a host's `window.route` shim must map
  `escalated.admin.workflows.create`, `.edit`, `.toggle` and `.reorder` to those
  paths.

### Changed
- Bump `ex_doc` from 0.40.3 to 0.40.4 (dev dependency). (#109)

### Added
- **`test/escalated/page_name_parity_test.exs`**, asserting every page name this
  package renders resolves to a component. It diffs them against the manifest
  the frontend publishes, vendored at `test/fixtures/escalated-pages.json`, and
  fails if its list of known-blank names still excuses one that has since been
  fixed, so that list can only shrink.

## [0.1.0] - 2026-09-12

### Fixed
- **Newsletter contact segmentation raised on PostgreSQL.** Every metadata rule
  went through `json_extract/2`, which is SQLite's spelling and SQLite's alone --
  PostgreSQL has no such function, and PostgreSQL is what nearly every Phoenix
  host runs. The rule now uses `->>` on PostgreSQL, `JSON_EXTRACT` on MySQL and
  `json_extract` on SQLite.

- **A duplicate ticket link raised instead of failing validation on PostgreSQL.**
  The unique index over `(parent_ticket_id, child_ticket_id, link_type)` gets a
  71-character generated name, and PostgreSQL truncates identifiers at 63 bytes,
  so the index on disk was called something `unique_constraint/2` never derived.
  The constraint violation escaped as `Ecto.ConstraintError` -- a 500 -- rather
  than coming back as a changeset error. SQLite keeps the full name and never
  noticed. New installs get a short explicit name; the changeset declares the
  legacy names too, so existing installs behave the same without a migration.

- **The snooze index could not be created on MySQL.** It is a partial index, and
  Ecto refuses those on MySQL outright, so the engine could not be installed
  there at all. MySQL now gets a plain index covering the same queries. (MySQL
  is still not supported overall -- see below.)

### Changed
- **The test suite runs on PostgreSQL as well as SQLite.** It had only ever seen
  SQLite, which is why none of the above was visible.
  `ESCALATED_TEST_ADAPTER` selects the adapter (`sqlite` default, `postgres`,
  `mysql`); an unrecognised value raises rather than falling back, because a CI
  leg that quietly ran SQLite would report green having tested nothing the
  matrix exists for. `mix test` now drops the schema before creating it, so a
  server-backed database starts each run as empty as an in-memory one.

  650 tests pass on both.

  **MySQL is not supported**, and there is no CI leg for it. The schema uses
  PostgreSQL array columns in eight places -- `{:array, :map}` for workflow and
  automation actions, `{:array, :string}` for webhook events and 2FA recovery
  codes, and so on -- and MySQL has no array type. Supporting it means changing
  those columns and the schemas over them, not adding a job. The code that could
  be made adapter-aware without that change now is.

### Added
- **Configurable database connection.** `:repo` now names the repo Escalated's
  own tables live on, and a new `:user_repo` names the repo your `user_schema`
  lives on. In Ecto the repo *is* the connection, so pointing `:repo` at a second
  repo is all it takes to keep support tables out of your primary database.

  `:user_repo` defaults to `:repo`, so a host that has not split its databases is
  unchanged — the same module, the same queries.

  Every user lookup in the package — the admin user list and role toggle, ticket
  requester and reply author resolution, mention matching, skill routing and the
  Skills form — now resolves `Escalated.user_repo/0` instead of
  `Escalated.repo/0`. On a split install `Escalated.repo/0` is a database with no
  users table in it, so a missed call site would not fail loudly; it would query
  the wrong database, which reads as users that do not exist.

  No query joins the two. No database can join across two connections: there is
  no `belongs_to` from an Escalated schema to the host's user schema, user ids
  are plain unconstrained columns, and every lookup resolves in two steps.
- Consume translation catalogs from the central `:escalated_locale` Hex package
  via a new `Escalated.Gettext` backend. Per-host overrides can be placed under
  `priv/gettext/overrides/{locale}/LC_MESSAGES/escalated.po`.

### Fixed
- Rename `ReportingService` floor/ceil helpers to avoid `Kernel` name conflict (#27)
- Close `split_ticket/3` with missing `end` so the module compiles (#26)
- Import `Ecto.Query` so `Customer.TicketController#show` compiles (#25)
- Attachment schema + migration + `url` field serialization (#18)
- Include computed ticket fields in serialization (#19)
- Include chat, context panel, and activity fields in serialization (#20)
- Include missing workflow and workflow log computed fields in serialization (#21)

### Added
- Parity with Laravel reference across tickets, workflows, chat, KB, reports (#17)
- Admin Users management page with admin/agent role toggles, mirroring `escalated-laravel#94`. Surfaces the host `users` table with `is_admin`/`is_agent` columns, paginated list with email/name search, and a PATCH endpoint that prevents self-admin-demotion.

### Internal
- Docker dev/demo environment under `docker/` with click-to-login agent picker and seeded profiles (#22, #28)

## [0.1.0] — initial release

Phoenix 1.7 + Ecto port of `escalated` reaching feature parity with the Laravel reference: tickets, workflow engine, chat, KB, reports, SLA tracking, and Inertia-driven Vue frontend served through the shared `@escalated-dev/escalated` package.
