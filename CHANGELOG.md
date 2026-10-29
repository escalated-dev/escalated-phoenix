# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Upgrading
- **Roles & permissions is now an install-level switch, off by default**
  (`config :escalated, access: [roles_permissions: true]`, or env
  `ESCALATED_ROLES_PERMISSIONS=true`; ADR 2026-10-29-configurable-access-features).
  Roles were stored but never enforced, so off is how every install already
  behaved, with these visible differences:
  - While it is off, the roles screens (`{prefix}/admin/roles*`) answer 404.
  - While it is off, the shared `escalated.permissions` prop is `["*"]` for
    staff (it was the slugs of the agent profile's role, which nothing
    enforced) and `[]` for everyone else. `escalated.features` gains
    `roles_permissions`, `two_factor` and `sso` (`sso` is always `false`:
    this package does not enforce it yet).
  - A user's permissions now come from the roles they hold in the new
    `role_user` table, not from their agent profile's `role`. Run the
    migration (`mix ecto.migrate`).
  To enforce roles: run the migration, seed the permissions and system roles
  (`mix escalated.seed_permissions`), give every staff user a role (start with
  `mix escalated.roles.assign you@example.com admin`), then set the switch.
  Passing the admin gate grants no permission by itself, so an admin without
  a role is refused everywhere. See docs/access-control.md.
- **Two-factor authentication is now an install-level switch, off by
  default** (`config :escalated, access: [two_factor: true]`, or env
  `ESCALATED_TWO_FACTOR=true`). Enrolments were stored but no login was ever
  challenged. While it is off, nothing is challenged and the new enrolment
  and challenge routes answer 404; enrolments are kept. To enforce it: set
  `:two_factor_secret` (32 bytes or more; `:guest_access_secret` is used when
  it is unset) so secrets and recovery codes are stored encrypted, run the
  migration (`mix ecto.migrate`, adds the nullable
  `two_factors.last_used_step`), then set the switch. Staff who already have
  an enabled enrolment are challenged from their next visit. If your login
  does not keep `"user_token"` in the session (as `mix phx.gen.auth` does),
  set `two_factor: [login_session_key: ...]` or call
  `Escalated.TwoFactorSession.forget/1` on login and logout, so every new
  login is challenged. See docs/access-control.md.
- `Escalated.Schemas.TwoFactor` now stores `secret` and `recovery_codes`
  encrypted (`Escalated.Types.EncryptedString`). Rows written before are read
  as they are and encrypted the next time they are saved.
  `TwoFactorService.enable/3` now records `verified_at`.
- `mix escalated.seed_permissions` now seeds escalated-laravel's whole
  permission set (`ticket.*`, `reply.*`, `kb.*`, ... `newsletters.*`) and a
  third system role, `light_agent`. The `agent` and `light_agent` roles get
  their default permissions on top of whatever they already grant.

### Added
- **Roles & permissions are enforced when switched on.** Every admin, agent
  and staff API route needs its permission from the user's roles as well as
  the host gate (`Escalated.Plugs.EnforceRoutePermissions`, map in
  `Escalated.RoutePermissions`; unmapped routes are refused, and a test checks
  every route is mapped). Status changes to `resolved`/`closed`/`reopened`
  also need `ticket.close`, bulk actions need each action's permission, and
  the staff API checks the token owner's permissions. Failing answers 403.
  While the switch is on, the newsletter screens check `newsletters.*` from
  the user's roles instead of letting every admin through.
- `mix escalated.roles.assign USER [ROLE]` gives a user a role by email or ID.
- `PUT {prefix}/admin/users/:user_id/roles` (needs `role.manage`, only while
  the switch is on) replaces a user's roles; you cannot remove your own
  `role.manage`. While roles are on, the users page also receives each user's
  `roles` and the assignable `roles`.
- **Two-factor is enforced when switched on.** A staff user with a confirmed
  enrolment must pass `Escalated/Auth/TwoFactorChallenge`
  (`GET|POST {prefix}/two-factor/challenge`, throttled to 5 attempts a minute
  per user) with a TOTP or single-use recovery code before any admin or agent
  route, once per login (`Escalated.Plugs.RequireTwoFactor`). JSON requests
  get 403 with `two_factor_required: true`. A TOTP code cannot be used twice.
  The token API is not challenged.
- `Escalated/Admin/Settings/TwoFactor` at `{prefix}/admin/settings/two-factor`
  (with `POST .../setup`, `.../confirm`, `.../disable`), open to every staff
  user: setup flashes `two_factor_setup: {qr_uri, recovery_codes}`, confirm
  flashes `two_factor_confirmed: {recovery_codes}`. Props `enabled`,
  `pending`, `required`.
- `config :escalated, two_factor: [required: true]` (env
  `ESCALATED_TWO_FACTOR_REQUIRED`), or the new `two_factor_required` general
  setting (which wins once saved), sends staff without an enrolment to enrol
  first. Shared prop `escalated.two_factor_required` is true for a user in
  that position.
- `mix escalated.two_factor.reset USER` removes a user's enrolment (lost
  device).
- TOTP uses `nimble_totp` (new dependency) for RFC 6238 codes, accepting one
  step of clock drift either side.
- `Escalated.AccessFeatures` (the three install-level switches) and
  `Escalated.Plugs.EnsureFeatureEnabled` (404 while a feature is off).

## [0.2.8] - 2026-10-28

### Upgrading
- Widget chat routes now answer an ended chat as escalated-laravel does. A
  widget or client that treated these 404s as "chat over" should read the 422
  (or the `ended: true` it already gets from `GET .../messages`). Chat grants
  are unchanged: they already expired and were stored hashed.

### Added
- Mobile guest API under `{prefix}/api/v1/mobile/guest` (only while the JSON
  API is mounted): `POST verification`, `POST lookup`, `POST tickets`,
  `GET tickets/:token` and `POST tickets/:token/replies`, per the shared
  contract (escalated-developer-context `domain-model/mobile-guest-api.md`).
  They reuse the verified guest access codes, grants and per-IP guest budgets,
  and answer with the allow-listed mobile ticket object. New
  `guest_tickets_enabled` setting (default `true`) turns the mobile guest
  ticket routes off. See docs/merchant-and-guest-access.md.

### Security
- `plug_crypto` is locked at 2.2.1 (EEF-CVE-2026-105963), which `mix hex.audit`
  now flags in 2.2.0.

### Changed
- `Escalated.Plugs.GuestPrivacy` also sets its headers just before a response
  is sent, so a plug later in the pipeline that answers on its own (a
  rate-limit 429) still sends `Cache-Control: private, no-store` and
  `Referrer-Policy: no-referrer`.
- `POST {prefix}/widget/chat/start` also returns `agent_name` (the assigned
  agent's name, or `null`), so its answer matches escalated-laravel's
  `{ id, session_id, expires_at, ticket_reference, status, agent_name }`.
- `POST widget/chat/{token}/messages` (and `/message`) and `/typing` on an
  ended chat answer 422 `{message: "Chat has ended."}` (was 404); a second
  `/end` answers 422 `{message: "Chat has already ended."}` (it ended the chat
  again and answered 200); `/rate` before the chat has ended answers 422
  `{message: "Chat must be ended before rating."}` (was 404); an empty or
  oversized message is 422 (was 404). An unknown or expired grant is still a
  404 on every chat route. The same applies to the `chat/sessions/{reference}`
  routes.

## [0.2.7] - 2026-10-22

### Fixed
- Transferring a live chat from the agent ticket page: the shared ticket page
  posts to `escalated.admin.chat.transfer` with the ChatSession's id
  (`chat_session_id`), but the only transfer route,
  `POST /agent/chat/sessions/:id/transfer`, is keyed by the chat ticket's id,
  so the transfer reached the wrong chat or none. New
  `POST /agent/chat/:session/transfer`, behind the agent check, takes the
  session id with the same body, checks and answers (404
  `{"message": "Chat session not found."}` for an unknown session). Upgrade:
  map `escalated.admin.chat.transfer` to `{prefix}/agent/chat/:session/transfer`
  in your `window.route` shim (see the README's UI Rendering section). The
  ticket-id route is unchanged.

## [0.2.6] - 2026-10-22

### Added
- End Chat from the agent ticket page (escalated-laravel
  `escalated.admin.chat.end`): `POST /agent/chat/:session/end`, behind the
  agent check like the rest of the chat console. `:session` is the
  ChatSession's id, which the ticket page carries as `chat_session_id`; the
  shared `ChatActionBar` posts `{}` there. Answers 200
  `{"message": "Chat ended."}`, 422 `{"message": "Chat is already ended."}`
  for a chat that is no longer waiting or active, and 404 for an unknown
  session. Phoenix has no Ziggy, so a host's `window.route` shim must map
  `escalated.admin.chat.end` to `{prefix}/agent/chat/:session/end`; without
  that mapping the End Chat button does nothing. The existing
  `POST /agent/chat/sessions/:id/end` (keyed by the chat ticket's id) is
  unchanged and keeps its response.
- Live chat transfer (escalated-laravel `escalated.admin.chat.transfer`):
  `POST /agent/chat/sessions/:id/transfer`, behind the agent check like the
  rest of the chat console (`:id` is the chat ticket's id). The body is
  `{"agent_id", "department_id"}` (either or both); the shared
  `ChatActionBar`'s `{"type": "agent" | "department", "id"}` is accepted too.
  With an agent, the session and ticket are reassigned to them (the agent must
  be able to see the ticket). With only a department, the ticket moves there
  and the chat goes back to the queue (unassigned, `waiting`) for routing. A
  closed chat, an unknown department, an invalid id or a missing target is a
  422. An internal system note records the transfer; the visitor's transcript
  does not show it. New `ChatSessionService.transfer_session/2`.
- `chat.transferred` is emitted to webhooks and workflows and offered in the
  webhook form and workflow builder (`Escalated.Events.emitted/0` is now every
  canonical name). Its `chat` payload adds `from_agent_id`, `to_agent_id` and
  `to_department_id`, as in Laravel. The chat PubSub topic gets
  `chat:transferred`.

## [0.2.5] - 2026-10-22

### Upgrading
- Run the new migration `20261026000001_create_api_tokens` (creates the
  tenant-owned `api_tokens` table; SQLite, PostgreSQL and MySQL). Nothing else
  changes: the API ignores these tokens until `api_tokens_enabled` is set, and
  host-authenticated setups (`current_user`, `:api_token_validator`) keep
  working with it on.

### Added
- API tokens, as escalated-laravel's: admins issue, rename, re-scope and revoke
  them on the shared `Admin/ApiTokens/Index` page (`/support/admin/api-tokens`,
  props `tokens`, `users`, `api_enabled`). Only the SHA-256 digest is stored;
  the token is shown once, in `flash.plain_text_token`. Tokens carry abilities
  (`agent`, `admin`, `*`), an optional 1-365 day expiry, and `last_used_at` /
  `last_used_ip` (written at most every five minutes). See `docs/api-tokens.md`.
- With `config :escalated, api_tokens_enabled: true`, the JSON ticket API
  (`/support/api/v1/tickets/*`) accepts `Authorization: Bearer <token>` and
  runs the request as the token's owner: 401 for an expired token or a missing
  owner, 403 for a token without the `agent` ability or an owner who is no
  longer an agent. A bearer value Escalated did not issue still goes to the
  host's `:api_token_validator`.
- `Escalated/Admin/Reports/AgentDetail` at `GET /admin/reports/agent/:id/detail`
  (`escalated.admin.reports.agent-detail`), the per-agent screen the agent
  ranking links to, admins only, with the props the shared page declares:
  `period_days`, `agent %{id, name, email}`, `total_tickets`,
  `resolved_tickets`, `avg_frt`, `avg_resolution`, `csat_score` (nil without
  ratings), `response_percentiles %{p50..p99}`, `productivity` (per day
  `%{label, value, values: [public replies, resolved]}`), `workload` (tickets
  created per day), `csat_breakdown` (`N stars` counts), and `prev_*` for the
  same number of days before. It reads `days` (or `period`, default 30).

## [0.2.4] - 2026-10-22

### Upgrading
- If `retention_closed_tickets` is set to anything but `never`, the next
  `mix escalated.purge_expired` run deletes the closed tickets it used to only
  report. Run it with `--dry-run` first to see the count. Schedule it daily
  from the host (cron, Quantum, Oban cron); the package schedules nothing.
- Run the migrations: `20261025000101_create_import_tables` adds
  `import_jobs` and `import_source_maps`, both tenant-owned.
- Set `:import_secret` (32 bytes or more) unless `:guest_access_secret` is set;
  starting an import refuses without one.
- Run the new migration `20261024000001_create_ticket_statuses`: it creates
  `ticket_statuses` (with one system row per built-in status for the
  single-tenant namespace; a merchant namespace gets its rows when its admin
  first opens the statuses page) and adds a nullable, indexed
  `ticket_status_id` to tickets (no foreign key, like `merged_into_id`).
  Existing tickets keep their status and get no custom status; nothing
  changes until an admin adds one.

- Run the new migration `20261022000001_add_business_schedule_refs` (adds the
  nullable `business_schedule_id` to SLA policies and departments). Nothing
  changes until a schedule exists: deadlines keep the configured hours.
  Once a schedule is marked default, business-hours deadlines use it.
- The package now depends on `tz` for time zone data. It is passed to the
  calculator explicitly and does not replace the host's time zone database.
- A policy's `business_hours_only` is reported from the package-wide
  `sla.business_hours_only` setting; a value posted with a policy is not
  stored, as business hours are not per policy here.
- Hosts reading the agent dashboard props directly: `recent_tickets` is now
  `recentTickets`, and `stats.my_open` / `stats.total_open` are now
  `stats.my_assigned` / `stats.open`.
- Ticket presence (who else is viewing) is kept per node for 60 seconds.
- Saving a webhook with the secret field left blank (or left out) now keeps
  the stored secret, because the edit form never receives it. Send
  `clear_secret: true` to remove it; any other value replaces it, as before.
  The shared frontend posts `secret: ''` with `clear_secret` and reads
  `webhook.has_secret`. This backend has no SSO settings, so there is no SSO
  mask to post back.
- The import pages' `job` (and each of `jobs`) is now exactly Laravel's field
  list: `user_id` and `updated_at` are no longer sent, and `error_log` is its
  last 50 entries.

### Added
- The admin Import wizard and the import framework behind it, as
  escalated-laravel's. The shared `Admin/Import/Index`, `Connect`, `Mapping`,
  `Review` and `Progress` pages render on Laravel's paths and props:
  `GET {prefix}/admin/import`, `GET /admin/import/:platform/connect`,
  `POST /admin/import/:platform/test-connection` (`{success[, error]}`, 422
  when the source raises), `GET /admin/import/:platform/mapping`,
  `POST /admin/import/:platform/review` (writes nothing),
  `POST /admin/import/:platform/start`, `GET /admin/import/progress/:job_id`,
  `GET /admin/import/status/:job_id` and
  `POST /admin/import/{pause,resume,cancel}/:job_id`. Admin only.
  - Sources are modules implementing the `Escalated.ImportAdapter` behaviour,
    added to the `"import.adapters"` filter (config `:filters` or an active
    plugin's `handle_filter/3`). Core ships none: a Zendesk or Freshdesk
    adapter comes from the host or a plugin.
  - `Escalated.Schemas.ImportJob` (status machine, per-entity progress and
    cursors, error log, sealed credentials) and `ImportSourceMap`, and
    `Escalated.Services.ImportService`, which skips what is already mapped (so
    a paused, failed or interrupted run resumes without duplicates), resolves
    references through the map and stops between batches when the job is
    paused or cancelled. Contacts the host has as users import as those users;
    others become `Escalated.Schemas.Contact`s on guest tickets.
  - Tested credentials wait in the session, sealed with a key derived from
    `:import_secret` (or `:guest_access_secret`), until the import starts, and
    are never sent to the browser. A completed or cancelled job drops them.
  - Runs are tasks under `Escalated.ImportTaskSupervisor`, carrying the
    request's tenant. Set `:import_dispatcher` to a 1-arity function to hand
    the job id to your own queue and call `Escalated.Import.Runner.run/1` there.
  - Import mode (`Escalated.Import.Context`, per process) holds back SLA
    attachment, breach and warning checks, escalation rules and automations.

- Custom ticket statuses (`Escalated.Schemas.TicketStatus`): admin-defined
  sub-statuses of five categories, `new`, `open`, `pending`, `on_hold` and
  `solved`. All lifecycle logic keys off the category: giving a ticket a
  custom status sets its built-in `status` to the category's anchor (`open`,
  `open`, `waiting_on_customer`, `in_progress`, `resolved`) and records the
  custom one in the new `ticket_status_id`, through
  `TicketService.transition_status/3`, so `resolved_at`/`closed_at`, SLA,
  the activity row, hooks, `ticket.status_changed` (plus `ticket.resolved`
  etc.), notifications and workflows all follow the anchor. A move between
  custom statuses with the same anchor is saved and announced with
  `ticket.status_changed`, without a second `ticket.resolved` and without
  re-stamping `resolved_at`. Setting any built-in status (snooze, merge,
  chat, reopen on reply...) clears the custom status.
  - The status inputs (agent and admin `status`, the bulk action,
    `PATCH /api/v1/tickets/:reference/status`, workflow `change_status`,
    macro and automation `set_status`/`change_status`) take a custom status's
    slug as well as a built-in status; unknown values are rejected as before.
    `TicketService.list/1` filters by a custom slug.
  - Staff ticket props (queue rows, `Agent/TicketShow`, `Admin/Tickets/Show`)
    and the API ticket JSON gain `custom_status` (`{id, label, slug, color,
    category}` or null) and `status_category`. The customer and guest views
    show the built-in status only.
  - The `status_changed` activity row records `custom_status` (the slug).
    Webhook payloads are unchanged.
  - `Escalated/Admin/Statuses/Index` (`statuses` by category then position,
    `categories`) and `Form` (`categories`, plus `status` on edit) at
    `/admin/statuses`, `/create` and `/:id/edit`, with store, update and
    delete, admin-only, with Laravel's validation. The slug is the label
    joined with `_`, de-duplicated with `_2`, `_3` (a built-in status's name
    counts as taken). `is_default` is exclusive within a category. The
    built-in statuses are listed as system rows: label, colour, description,
    position and the default flag can be edited; slug and category cannot,
    and they cannot be deleted.
  - Deleting a custom status leaves its tickets in their built-in status with
    no custom status. Changing a status's category does not move tickets
    already in it; tickets given it afterwards take the new anchor.

- Custom fields and custom objects (escalated-laravel's `CustomField`,
  `CustomFieldValue`, `CustomObject` and `CustomObjectRecord`). The schemas
  and tables existed; nothing used them.
  - Custom field admin: `Admin/CustomFields/Index` (`fields`, by position) and
    `Form` (`contexts`, plus `field` on edit) at `/admin/custom-fields`,
    `/create` and `/:id/edit`, with store, update, delete and
    `POST /admin/custom-fields/reorder` (`positions: [{id, position}]`).
    Fields serialise under Laravel's names (`type`, `context`, `required`,
    `active`, ...); the existing columns (`field_type`, `entity_type`,
    `is_required`, `is_active`) are mapped, not renamed. A new field's slug is
    its name joined with `_` (`order_number`), de-duplicated with `_2`, `_3`.
    Select and multi-select fields need at least one option. Deleting a field
    deletes its values.
  - Ticket values: the customer create (`POST /tickets`), the JSON API create
    (`POST /api/v1/tickets`) and the new agent update
    (`PUT|PATCH /agent/tickets/:reference`, Laravel's
    `escalated.agent.tickets.update`: `subject`, `description`,
    `custom_fields`) take `custom_fields`, an object keyed by field slug (a
    numeric field id and the camelCase `customFields` key work too). Only
    active `ticket` fields count; other keys are refused. Required fields are
    enforced on create; on update only the keys sent are checked. `number`,
    `date` (`YYYY-MM-DD`), `checkbox`, `select`, `multi_select` and `text`
    (<= 255) values are checked before the ticket is written, with errors keyed
    `custom_fields.<slug>`. An empty optional value deletes the stored one.
    With no fields defined, every request behaves as before.
  - `Customer/Create` gets the `custom_fields` definitions;
    `Customer/Show`, `Agent/TicketShow`, `Admin/Tickets/Show` and the API
    ticket detail get them with the ticket's decoded `value`.
  - Custom object admin: `Admin/CustomObjects/Index` (`objects` with
    `records_count`), `Form` (`object`) and `Records` (`object`, `records`
    newest first) at `/admin/custom-objects`, with record store, update and
    delete under `/admin/custom-objects/:id/records`. Record `data` is checked
    against the object's `fields_schema` (errors keyed `data.<name>`); a record
    of another object is a 404; deleting an object deletes its records.
  - Upgrade notes: run the new migration (`placeholder`, `validation_rules` and
    `conditions` on the custom fields table). `fields_schema` is stored in the
    existing `field_definitions` column as `{"fields": [...]}`; a row written
    before as a map of definitions reads back as a list. Slugs generated by
    `CustomField.changeset/2` now use `_` instead of `-`; existing slugs are
    unchanged. Guest and widget ticket creation do not take custom fields yet.
  - Flash messages use this package's `:info` key, as every other admin page
    here does.
- Business hours and holidays (escalated-laravel's `BusinessSchedule`,
  `Holiday` and `BusinessHoursCalculator`). A schedule has a time zone, opening
  hours per weekday and holidays (one date, or every year on that day).
  - SLA deadlines count against a schedule when business hours apply
    (`sla.business_hours_only`): the policy's `business_schedule_id`, else the
    ticket department's, else the default schedule. With no schedule set up,
    the configured `sla.business_hours` apply exactly as before.
  - `Escalated.Services.BusinessHoursCalculator` counts business time in the
    schedule's zone: weekends and holidays are skipped, a ticket that arrives
    after hours starts at the next opening, `24:00` closes at midnight, an end
    before the start is an overnight shift, and daylight-saving days are
    measured in real time. A schedule with no opening hours at all falls back
    to calendar time.
  - `Admin/BusinessHours/Index` and `Form` render at `/admin/business-hours`,
    `/create` and `/:id/edit` with Laravel's props (`schedules` with their
    `holidays`, `schedule`, `timezones`). Store and update take `name`,
    `timezone`, `is_default`, `schedule` and `holidays`; making a schedule the
    default unsets the previous one, update replaces the holidays, and delete
    clears the schedule from policies and departments.
  - SLA policies and departments take `business_schedule_id`; a save that does
    not send it leaves it alone, and an id that names no schedule is a field
    error. The `Admin/SlaPolicies/Form` and `Admin/Departments/Form` pages
    receive a `schedules` prop (`[{id, name}]`, by name) for the shared
    frontend's **Business hours schedule** picker, and the department form's
    `department` carries `business_schedule_id`.
  - Departments: `GET /admin/departments/:id/edit` renders the form (the shared
    Index links there), and store/update take the shared form's flat fields as
    well as the older nested `department` body. A failed Inertia save goes back
    with field errors; non-Inertia requests answer as before.

- The admin Settings sub-pages the shared UI ships, with escalated-laravel's
  props, routes and validation (all admin-only, saved in the existing
  `escalated_settings` store):
  - `Escalated/Admin/Settings/DatabaseConnection` at `/admin/settings/database`:
    a read-only view of the repo Escalated's tables live on (`connections`
    with one entry, `current`, `hostDefault`, `pinnedByConfig: true`,
    `tablePrefix`). The repo is set in config, so `POST
    /admin/settings/database` only answers with an error flash, and `POST
    /admin/settings/database/test` describes it as JSON. Not served with
    tenancy enabled (Laravel shows it to platform admins only).
  - `Escalated/Admin/Settings/EmailSettings` at `/admin/settings/email`:
    `addresses` (`email`, `display_name`, `department_id`, `dkim_status`) and
    `defaultReplyAddress`, kept in the `email_addresses` and
    `default_reply_address` settings. Stored only, as in Laravel: outbound mail
    and the `email_channels` table are unchanged.
  - `Escalated/Admin/Settings/PublicTickets` at `/admin/settings/public-tickets`
    over the guest-policy keys the widget already reads. The page posts, so
    `POST` is accepted beside the existing `PUT`.
  - `mix escalated.purge_expired` now enforces closed-ticket retention as well
    (`Escalated.Services.RetentionPurge`), see Changed.

### Changed
- `mix escalated.purge_expired` deletes closed tickets older than
  `retention_closed_tickets` (it only reported them before), with their
  replies, activities, attachments and stored files, tags, followers,
  ratings, links, side conversations, workflow logs, delayed actions, guest
  grants and custom field values. The ticket schema has no soft delete, so
  unlike Laravel there is no 30-day grace period. Every retention setting
  still defaults to `never`, which deletes nothing. Purged attachments'
  local files are removed too. `--dry-run` reports without deleting.
- `GET /admin/settings/public-tickets` renders the shared page; a JSON client
  (`Accept: application/json`, not an Inertia visit) still gets the JSON
  settings. Saves are validated as in Laravel: an unknown
  `guest_policy_mode` or `guest_user` without a user id is now refused (a
  422 for JSON clients, field errors for the page) instead of being coerced
  to `unassigned`.
- CSAT and data-retention saves are validated as in Laravel (scale, trigger,
  delay 0..168, retention options, `retention_user_data_gdpr` required
  boolean) and a failed Inertia save goes back with field errors.
  `csat_delay_hours` is rendered as an integer.

### Fixed
- `Escalated/Admin/Settings/DataRetention` gets its purge preview as
  `purgePreview`, the prop the page reads (it was sent as `purge_preview`, so
  the counts always showed 0).
- The ticket pages now get the props the shared Vue pages read
  (escalated-laravel's Agent, Admin and Customer `TicketController` and agent
  `DashboardController`):
  - `Admin/Tickets/Index` sent a bare list, so the admin queue rendered no
    tickets. Both queues now send Laravel's length-aware paginator (`page`,
    `per_page`) of rows carrying `requester`, `assignee`, `department`, `tags`,
    `latest_reply` and the SLA fields, plus `departments` and `tags`; the admin
    queue adds `agents` and `savedViews`.
  - `Admin/Tickets/Show` sent the replies and activities beside the ticket,
    where the page never looks. Both show pages now put `replies` (newest
    first, with `author` and `is_internal_note`), `pinned_notes`, `activities`,
    `satisfaction_rating` and `sla_policy` on the ticket, and send
    `departments`, `tags`, `cannedResponses`, `macros`, `is_following` and
    `followers_count`. Admin adds `agents` and `is_snoozed`.
  - `Agent/Dashboard` sends `stats` (`open`, `my_assigned`, `unassigned`,
    `sla_breached`, `resolved_today`), `recentTickets`, `needsAttention` and
    `myPerformance` in place of `recent_tickets` and the old stat keys.
  - `Customer/Index` sends a paginator; `Customer/Show` sends the requester-safe
    allow-list (no internal notes, staff by display name, no assignee or
    metadata), with `department` and `satisfaction_rating`.
- Admin configuration pages:
  - SLA policies have admin pages for the first time (`Admin/SlaPolicies/Index`
    and `Form`, at `/admin/sla-policies`, `/create` and `/:id/edit`), with the
    props Laravel's `SlaPolicyController` sends: `policies` with
    `tickets_count`, then `priorities`, `targeted`, `departments` and
    `ticketTypes`. Deleting a policy unlinks its tickets.
  - `Admin/Webhooks/Form` renders at `/admin/webhooks/create` and
    `/:id/edit`.
  - The webhook index sends each webhook's recent `deliveries`, which is where
    the page reads the last delivery.
  - `Admin/Webhooks/DeliveryLog` sends a paginator with `created_at`.
  - Retry also answers on Laravel's `/admin/webhooks/deliveries/:id/retry`.
  - The escalation rule index lists inactive rules as well, and
    `/admin/escalation-rules/create` and `/:id/edit` render the form.
  - Failed SLA policy, escalation rule and webhook writes from an Inertia form
    go back with the errors in the session. JSON clients still get a 422.
- Knowledge base pages:
  - `Admin/KnowledgeBase/Articles/Form` renders at `/admin/kb-articles/create`
    and `/:id/edit`.
  - The admin and reader article lists send paginators (the pages read
    `articles.data`), and each article carries its `category`.
  - Reader categories carry `articles_count`, and both reader pages send
    `feedbackEnabled`. These replace `article_count` and `feedback_enabled`,
    which the pages never read.
  - Article feedback redirects back to the article for an Inertia visit.
  - The admin pages' own paths, `/admin/kb-articles` and
    `/admin/kb-categories`, are mounted. The `/admin/kb/...` paths stay.
- Guest portal pages on the existing verified guest access:
  - `GET {prefix}/guest/create` renders `Guest/Create` with `departments`,
    `priorities`, `verification_url` and `lookup_url`.
  - `POST {prefix}/guest` creates the ticket from the verified form. It
    consumes the email code exactly as the JSON guest API does, then redirects
    to the ticket's private link. A bad code goes back with a
    `verification_code` error.
  - `GET {prefix}/guest/:token` renders `Guest/Show`. It sends the
    requester-safe ticket with `guest_access_expires_at`, guest attachment
    URLs and the `token`. A bad, expired or revoked token is a 404.
  - `POST {prefix}/guest/:token/reply` replies as the guest, and refuses closed
    tickets.
  - `POST {prefix}/guest/:token/rate` rates the ticket.
  - The guest rate limits and privacy headers apply to all of these.
- A CSAT rating posted as an Inertia visit, from the customer or guest page,
  redirects back to the ticket instead of answering JSON.
- `Admin/Workflows/Logs` renders at `/admin/workflows/logs` with `logs` and
  `workflows`, newest first, optionally filtered with `?workflow=id`. Each log
  carries `workflow_name`, `ticket_reference`, `event`, `matched`, `status`,
  `duration_ms`, `error`, a count in `actions_executed` and the actions in
  `action_details`. `/admin/workflows/:id/logs` redirects to the filtered
  page. `Admin/Workflows/Builder` is not rendered, and neither does Laravel
  render it; the builder lives inside `Workflows/Form`.
- Report screens. Each takes `days` (or `period`) and defaults to 30 days:
  - `Admin/Reports` at `/admin/reports`
  - `Reports/Dashboard` at `/reports/dashboard`
  - `AgentMetrics` at `/reports/agents`
  - `SlaReport` at `/reports/sla`
  - `CsatReport` at `/reports/csat`
  - `Comparison` at `/reports/comparison`
  - `ResponseTimes` at `/reports/response-times` and `/reports/frt`
  - `ResolutionTimes` at `/reports/resolution-times` and `/reports/resolution`
  - `AgentRanking` at `/reports/agent-ranking`
  - `SlaTrends` at `/reports/sla-trends` (`group_by` day, week or month)
  - `Cohorts` at `/reports/cohorts`

  Each sends the props escalated-laravel's `ReportController` sends:
  - Charts get `%{label, value}` lists.
  - Agent tables get `agent_id` and `agent_name`, resolved from the host's
    users.
  - Which SLA deadline was missed is derived from the due dates, as this
    backend keeps one `sla_breached` flag. A ticket counts as breached when
    the flag is set or either deadline was missed.

  Not yet rendered: `Reports/AgentDetail`. Report exports are not available.
- `Admin/AuditLog/Index` renders at `/admin/audit-log`.
  - It sends `logs` as a paginator of 50 a page, newest first. Each log
    carries `auditable_type`/`auditable_id` (this backend's
    `entity_type`/`entity_id`) and the acting `user`.
  - It also sends `filters`, `users`, `actions` and `resourceTypes`.
  - Filters: `user_id`, `action`, `auditable_type`, `date_from`, `date_to`.
  - `users` lists the people who appear in the log, not every host user.
- Not rendered, because this backend has no such feature:
  - `Admin/CustomFields/*` and `Admin/CustomObjects/*`. They exist as tables
    only.
- Roles have admin pages (`Admin/Roles/Index` and `Form`, at `/admin/roles`,
  `/create` and `/:id/edit`): `roles` with `users_count` (active agent
  profiles holding the role), and `permissions` grouped by `group`. Store and
  update take `name`, `description` and `permissions` (ids), replace the role's
  permissions, and refuse unknown ids; system roles cannot be deleted.
- Not rendered, because this backend has no such feature: `Admin/ApiTokens/Index`
  (API tokens are validated by the host's `api_token_validator`; there is no
  token store).
- Not rendered, because this backend has no such feature: `Admin/Statuses/*`.
  Statuses are a fixed set here.
- The writes the ticket pages post now have routes: `status` and `priority` as
  POST (the PATCH routes stay), `follow`, `macro`, `presence` and
  `replies/:reply_id/pin` on both desks, POST `tags`/`department` on the admin
  desk, and customer `close`/`reopen`. Customer ticket creation reads the flat
  form the shared Create page posts; snooze and unsnooze redirect back for an
  Inertia visit.
- `test/fixtures/escalated-pages.json` is refreshed to frontend 0.12.3 and the
  page-name parity test keeps a ledger of the shipped pages not rendered yet.

### Security
- **Stored secrets are guarded from every admin page.** Saving a webhook with
  the secret field left blank, which is what the edit form sends since it
  never shows the secret, silently removed the signing secret; it is now kept
  (see Upgrading). The webhook pages and import pages already sent
  `has_secret` and an explicit job field list rather than the secret or the
  credentials; a new router-level test (`SecretsNeverSerializedTest`) now
  checks the webhook index, edit and delivery-log pages, every import step and
  the status JSON, and the settings pages for the raw secret, so a later
  change cannot start sending it. `Webhook.secret`, `ImportJob.credentials`
  and `TwoFactor.secret` / `recovery_codes` are now `redact: true`, so they
  no longer appear in `inspect/1` output (logs, crash reports). None of these
  schemas has a JSON encoder. Not applicable here: SSO settings and API token
  stores do not exist in this backend, and inbound email secrets are host
  config, not a stored setting.

## [0.2.3] - 2026-10-21

### Upgrading

- Run the new migration
  `20261021000001_add_ticket_merged_into` (adds the nullable
  `tickets.merged_into_id` column and its index) before deploying; the ticket
  schema reads the column.
- Nothing is emailed until `mailer` or
  `notification_delivery` is configured, so existing installs are unchanged.
  Once one is set, requesters receive a confirmation for every ticket they
  open, including tickets created from inbound email.
- Workflows saved with a trigger nothing used to fire (for
  example `ticket.updated` or `ticket.assigned`, which the old builder did not
  offer but the API accepted) start running. Review inactive-looking workflows
  before upgrading. A `ticket.updated` workflow runs on every field change an
  agent, rule or delayed action makes; changes a workflow makes while it runs
  still trigger no further workflows.

### Added

- Live chat events (ADR 2026-10-21): `ChatSessionService` now emits
  `chat.started`, `chat.assigned`, `chat.message` and `chat.ended` through
  `Escalated.Events.emit/2`, so they reach outbound webhooks and workflows
  (they were not emitted at all), and the webhook admin and the workflow
  builder offer them. There is no chat transfer in this package, so
  `chat.transferred` is neither offered nor emitted. The webhook payload is
  `%{chat: %{session_id, ticket_id, status, agent_id, department_id}}`, plus
  `reply_id`/`author_type` (`agent` or `visitor`) for a message and
  `ended_by` (`agent`, `customer` or `system` for an idle close; new
  `:ended_by` option on `end_session/2`) for an end. It never carries the
  visitor's chat token, the visitor's email or the message body. Workflows on
  chat events run against the chat's ticket. Webhooks and workflows saved
  under `chat.session_started` / `chat.session_ended` receive `chat.started` /
  `chat.ended`. The PubSub chat broadcasts are unchanged.
- Ticket merge, as escalated-laravel's `TicketMergeService`:
  `Escalated.Services.TicketMergeService.merge/3` moves the source's replies
  and notes (and their attachments) to the target, adds a system note to both
  tickets, and closes the source with `merged_into_id` set, in one
  transaction; the close is then announced like any status change
  (`ticket.status_changed`, `ticket.closed`). Self-merges, re-merges and
  merges into a merged ticket are refused. Admin routes for the shared merge
  dialog: `GET {prefix}/admin/tickets/merge-search?q=` and
  `POST {prefix}/admin/tickets/:reference/merge` (`target_reference`).
- Bulk ticket actions for the shared `BulkActionBar`:
  `POST {prefix}/admin/tickets/bulk` and `POST {prefix}/agent/tickets/bulk`
  with `{ticket_ids, action, value}` (`status`, `priority`, `assign`, `tags`,
  `department`, and `delete` for admins), each ticket through the usual
  services.
- `TicketService.announce_status_change/3`.
- Outbound notification emails, sent through the host's mailer:
  `config :escalated, mailer: MyApp.Mailer` (a Swoosh mailer) or
  `notification_delivery: &fun/1`. New ticket (requester and assignee), public
  reply (requester, assignee and followers, never the author), assignment
  (assignee), status change (requester and followers, never whoever changed
  it), escalation (assignee) and SLA breach (assignee), following
  escalated-laravel's notification listeners. Each carries the
  `Escalated.Emails.TicketEmail` threading headers and branding, and a signed
  `Reply-To` when `email_inbound_secret` is set. Internal notes and live chat
  messages are not emailed. `notification_channels` without `:email` turns it
  off. See `docs/notification-emails.md`.
- `TicketService.reply/3` takes `notify: false` (no email for this reply) and
  `author: :system` (a reply with no author written by Escalated itself).
- `Escalated.Emails.TicketEmail.notice_email/4` and
  `threading_headers_for_notice/1`.
- Workflows run on every event this package emits, under the canonical names
  of the shared event vocabulary (escalated-developer-context
  `decisions/2026-10-21-event-vocabulary.md`): `ticket.updated`,
  `ticket.assigned`, `ticket.unassigned`, `ticket.priority_changed`,
  `ticket.department_changed`, `ticket.tag_added`, `ticket.tag_removed`,
  `ticket.resolved`, `ticket.closed`, `ticket.reopened`, `ticket.escalated`,
  `note.created`, `sla.warning` and `sla.breached` join `ticket.created`,
  `reply.created` and `ticket.status_changed`. The builder offers exactly
  these. `Escalated.Events` holds the names and `Escalated.Events.emit/2`
  announces each event to webhooks and workflows alike.
- The workflow builder offers the `delay` action. A saved delay now defers the
  actions after it (`mix escalated.run_due_delayed_actions` runs them); before,
  the runner called the executor without the workflow id a delay needs, so the
  delay failed and the later actions were skipped. The minutes may be a number,
  a numeric string or `{"minutes": n}`.

### Changed

- Legacy event names are read as their canonical names: a workflow stored as
  `ticket.replied`, `ticket.tagged` or `internal_note.added`, or a webhook
  subscribed to them, runs on / receives `reply.created`, `ticket.tag_added`
  and `note.created` (likewise `ticket.untagged`, `tag.added`, `tag.removed`,
  `internal_note.created`, `chat.session_started`, `chat.session_ended`).
  Workflows and webhooks saved through the admin are stored under the
  canonical name, and the admin shows stored legacy names canonically. No
  migration is needed.
- Replies and notes written by a workflow (`add_note`, `insert_canned_reply`,
  including from a delayed action) run no workflows, so a `reply.created` or
  `note.created` workflow cannot answer itself.

## [0.2.2] - 2026-10-20

### Changed
- The bundled widget is now `@escalated-dev/escalated` 0.12.3. It keeps its script settings when `embed.js` is placed in the page `<head>`, and Enter no longer picks a stale mention suggestion.

### Fixed

- Automation and macro "add note" actions now create internal notes. They
  passed `is_internal_note`, which the reply schema does not cast, so every
  such note was saved as a public reply the requester could read.
  `Reply.changeset/2` now raises on `is_internal_note` and similar aliases
  instead of silently dropping them.
- Escalation rules, automations and macros change status, priority, assignee
  and department through `TicketService` / `AssignmentService`, so their
  webhooks (`ticket.status_changed`, `ticket.resolved`, `ticket.escalated`,
  `ticket.priority_changed`, `ticket.assigned`, `ticket.department_changed`,
  `ticket.updated`), hooks, activity rows, workflows and assignment checks run
  as they do for a change an agent makes. Setting a value the ticket already
  has is a no-op.
- `GET {prefix}/widget/config` answers `403 {"enabled": false}` while the
  widget is disabled, matching Laravel (it answered 200). The widget stays
  enabled by default (`widget_settings.enabled`); Laravel defaults it off, but
  flipping the default here would silently turn the widget off on existing
  installs.

### Security

- Outbound webhook URLs must be http or https and resolve only to public
  addresses. Loopback, private, link-local (cloud metadata), carrier-grade NAT,
  multicast and other reserved ranges are refused when a webhook is saved and
  again before every delivery; a refused delivery is recorded as not sent and
  not retried. The default client connects to the checked address (keeping
  the host name for the Host header and TLS verification) and no longer
  follows redirects. Hosts can replace DNS resolution with
  `config :escalated, :outbound_url_resolver, fun`.

## [0.2.1] - 2026-10-19

### Changed
- The bundled widget is now `@escalated-dev/escalated` 0.12.2. It hides its Check Status tab when `/config` returns `status_lookup_enabled: false`.

### Security

- Require Decimal 3.1.2 or newer below 4.0 to exclude CVE-2026-97853, including
  installations in host applications. The lockfile uses Decimal 3.2.0.
- Require Ecto SQL 3.14 or newer in the 3.x line because earlier Ecto lines
  select Decimal 1.x/2.x, which do not have that security fix. Existing hosts
  must update their Ecto and Decimal dependencies together.

### Added

- Opt-in department and account ticket visibility across UI/API/widget queries, related records, reports, bulk operations, assignment, mentions and live channels. Admins retain access; all settings default off.
- Host account resolvers and nullable indexed ticket account fields; account/type conditions in workflows, automations and escalation rules.
- Opt-in department/type SLA targets, with explicit reselection from the original ticket creation time. Moving a ticket preserves existing deadlines.
- Additive migration and regression coverage for SQLite, PostgreSQL, MySQL, custom prefixes, separate host databases and string identities. See `docs/ticket-access-and-routing.md` for configuration and integration hooks.
- Cross-origin widget embedding, off until a site is listed. Allowed sites come
  from `config :escalated, widget_allowed_origins` (a list or a comma separated
  string, e.g. `ESCALATED_WIDGET_ALLOWED_ORIGINS`) plus the new
  `widget_allowed_origins` admin setting, which is validated on save. Requests
  from those sites get CORS headers on every widget answer (preflights, 4xx and
  429 included), skip the CSRF check and always run as guests. New
  `Escalated.Plugs.WidgetCors` and `escalated_widget_routes/1` (with
  `escalated_routes(prefix, widget: false)`) let hosts mount the widget in its
  own pipeline; routers that only call `escalated_routes/2` keep working.
- `GET /widget/embed.js` serves the standalone widget bundle from
  `@escalated-dev/escalated` 0.12.1 with caching headers and an ETag.
- `/widget/config` returns `accepts_metadata: true`; widget tickets and chats
  store the sanitised `metadata` the embedding page sends, plus the server-set
  `embedded_on` origin. Widget tickets keep `source: "widget"`. See
  `docs/embedding-the-widget.md`.
- Widget routes answer in the shape the shared widget reads. `/widget/config`
  adds `color`, `position`, `departments`, `kb_enabled`,
  `guest_tickets_enabled` and `status_lookup_enabled: true`
  (`primary_color` stays). New `GET /widget/articles?q=` and
  `GET /widget/articles/:slug` serve published knowledge-base articles and
  follow the knowledge base's enabled and public settings. Widget tickets and
  chats accept `department_id` (ignored unless it names an active department).
  Chat messages carry `author.name`, and the verified ticket view adds
  `status_label`, `status_color`, `department` and each reply's `author` and
  `is_agent`.

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
