# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
