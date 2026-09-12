# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
