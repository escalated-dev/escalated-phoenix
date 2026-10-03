# Merchant tenancy and verified guest access

These source changes require the September 30, 2026 migrations and compatible
shared frontend code (tenant broadcasts #184 and guest forms #186/#187). They do
not activate tenancy, migrate production files or publish a package themselves.
Apply every package migration to the configured support repository before using
the new code. The migrations preserve legacy rows in the reserved empty namespace.

## Trusted host contract

```elixir
config :escalated,
  repo: MyApp.SupportRepo,
  user_repo: MyApp.Repo,
  user_schema: MyApp.Accounts.User,
  tenancy_enabled: true,
  tenant_resolver: MyApp.SupportTenantResolver,
  guest_access_secret: System.fetch_env!("SUPPORT_GUEST_ACCESS_SECRET"),
  guest_verification_delivery: &MyApp.SupportMail.deliver_code/3,
  guest_reference_resolver: &MyApp.Shipments.support_ticket_ids/3
```

The resolver must implement:

| Callback | Required behavior |
| --- | --- |
| `resolve(conn)` | Return a tenant ID or `{:ok, id}` from trusted host routing/session state. An unknown tenant is denied. Authenticate inbound integration routing before resolving it. |
| `member?(user, tenant_id)` | Return exactly `true` only for current membership. Query current host state so removal takes effect on new requests and realtime messages. Membership alone does not grant staff access. |
| `reference?(:user, id, tenant_id)` | Check that a referenced requester, author or agent belongs to this tenant on the host database. Assignment also requires a staff seat. |
| `reference?(type, id, tenant_id)` | Authorize host-owned subject/entity references, such as a shipment or order. Unknown types must return false. |
| `scope_users(query, tenant_id)` | Return an Ecto query limited to current tenant members. Its joins stay on the host repository; never join host users into the support database. |
| `tenants()` | Return the explicit tenant ID list for scheduled maintenance. Alternatively select one tenant with `--tenant ID`. |
| `public_url(tenant_id)` | Return the merchant's trusted HTTPS origin and support mount path for newsletter links, for example `https://merchant.example/support`. Required when generating merchant newsletter links; a global URL is never a fallback. |

IDs are case-sensitive, nonempty UTF-8 strings of at most 128 bytes, with no
leading/trailing whitespace or NUL. Do not trust a submitted `tenant_id`, a socket
topic or a guest email as membership. Public guest pages may use a host-validated
merchant domain or public account route; mailbox proof still gates correspondence.

Package routes resolve context before controller work and clear it after response.
Bearer authentication rechecks membership after resolving the user. Direct jobs
and services must establish their trusted context explicitly:

```elixir
Escalated.Tenancy.run(tenant_id, fn ->
  Escalated.Services.TicketService.list(%{})
end)
```

Missing context fails closed. `Tenancy.capture/1` captures context for a spawned
callback. Arbitrary spawned processes do not inherit it. Do not pass unvalidated
record structs between tenants. `Escalated.repo/0` scopes package reads, joins,
preloads, writes, bulk mutations and `Ecto.Multi` operations. It checks the
package foreign keys and host references a write stores: an insert checks all of
them, an update only those it changes, and a delete none, so a row that still
names a user whose membership was revoked can still be updated or deleted. The
scoped repo has no raw SQL entry point (`query/3` and friends), and it refuses
subqueries/CTEs/unions, query or placeholder values in `insert_all` rows,
outer/association joins, prefix overrides and bulk ownership changes; use
supported queries or separately scoped queries and combine their results in
Elixir. SQL written inside `fragment/1` is trusted raw SQL: the scoped repo does
not inspect it, so a fragment that selects from another table is not tenant
scoped. Only use fragments whose SQL reads the row already in scope.
`storage_repo/0` is a trusted host migration escape hatch, not a request-facing
API. Host code and plugins that query their own repo directly remain responsible
for their own authorization.

Tenant mode requires explicit booleans. Keep it enabled for a merchant database;
turning it off restores the legacy single-tenant API and is not an isolation mode.

## Provisioning and upgrading

For a new merchant, create host membership first, then run
`Escalated.Tenancy.Provisioner.seed/0` inside its tenant context. It creates the
permission catalog and admin/agent roles idempotently. It grants no staff seat.
Provision an active `Escalated.Schemas.AgentProfile` for each approved host user
with role `"admin"` or `"agent"` through `Escalated.repo/0` inside that context.
The host owns seat administration. The legacy host-user role toggle and generic
platform plugin administration/execution are unavailable in tenant mode.
Explicit `agent_check`/`admin_check` callbacks may implement host roles, but must
consider the current tenant. Package membership checks still apply.

An existing single-tenant installation is never automatically assigned to the
first merchant that signs in. Choose its owner explicitly:

```sh
mix escalated.backfill_tenant --tenant merchant-id
# Review the counts and reference errors, stop all HTTP/job/inbound writers:
mix escalated.backfill_tenant --tenant merchant-id --apply --writers-stopped
```

Preview only reads. Apply validates an empty destination and all registered
references, then assigns every legacy tenant table in one transaction. Fix
unresolved host references before retrying. This is a whole-installation migration;
splitting an already mixed legacy database requires an explicit host migration.
The command does not move attachment files. Take an ordinary backup before a
production migration. Downgrading the tenancy migration refuses assigned rows;
it cannot merge merchant data back into the legacy namespace.
The guest-access migration separately refuses rollback while any challenge,
grant or mailbox-budget record remains. Let active records expire and run the
bounded cleanup for every tenant before retrying an empty-state downgrade; a
rollback never silently clears those proof or abuse-control records.
Backfill an existing installation before provisioning destination roles: the
destination must be empty for this whole-installation operation.

Scheduled tasks accept `--tenant ID`, or sweep the resolver's trusted catalog:
SLA checks, delayed workflows, escalation, snoozed tickets, retention, newsletters
and permission seeding. Each operation runs with a restored tenant context. A
tenant whose operation fails is logged by tenant ID and error type, the sweep
continues with the remaining tenants, and `Escalated.Tenancy.Maintenance.Error`
listing the failed tenants is raised at the end, so the task exits non-zero.
Settings, contacts, roles and other formerly global unique keys are tenant-local.

## Realtime

Register `channel "escalated:tenant:*", Escalated.Channels.TenantChannel` in the
host socket. Authenticated `connect/3` sets `:current_user` and
`:escalated_tenant_id` from trusted host state. Use the shared frontend's
`escalated.broadcasting.channel_prefix`, or `Tenancy.topic/1`, to form topics.
Topics contain a hash of the tenant ID. Old unscoped topics are refused in merchant
mode. Membership and ticket ownership are rechecked for incoming and outgoing
messages. Customer ticket events omit internal notes and staff metadata.

The shared frontend's optional realtime client currently uses `window.Echo`.
A host using Phoenix sockets must supply its Echo-to-Phoenix bridge (including
the dotted frontend suffix to colon topic mapping), or keep the supported HTTP
polling fallback. This package does not install a browser socket bridge. When
using `ShareInertiaData` in a host pipeline, resolve the tenant before that plug.

Merchant guest chat uses HTTP polling with its expiring capability. Anonymous
merchant socket joins are deliberately denied. Platform PubSub subscriptions
outside these channels must use the same tenant context and authorization.

## Mailbox proof and guest capabilities

Set `guest_access_secret` to at least 32 random bytes and keep it stable across
nodes. Configure `guest_verification_delivery.(email, code, purpose)` to send the
code through the host mailer and return `:ok` or `{:ok, value}`. Never log codes or
live capabilities. Missing configuration fails closed. Rotation invalidates
existing capabilities and pending proofs.

1. POST `/support/guest/verification`, `/support/api/v1/guest/verification` or
   `/support/widget/verification` with `{email, purpose}`. Purpose is `ticket`,
   `chat` or `lookup`. A 202 response contains `verification_id` and `expires_in`.
2. Submit the received `verification_code` and `verification_id` with the same
   email and intended create/lookup request. Codes expire after ten minutes and
   allow five attempts; every wrong code and the first successful use spend one.
   Proof consumption and creation commit together. Within the ten minutes, an
   identical retry (same code, email and request) spends no attempt and returns
   the original result without a second ticket, chat or creation event. Its
   `guest_access_token` is a freshly sealed capability for the same grant and
   expiry, so it may differ byte-for-byte from the first response; both work.
   A retry after that grant was renewed, revoked or expired, a changed request,
   or any request after five spent attempts is refused with 422. The proof row
   stores only non-secret result data (ticket IDs, references, subjects, expiry),
   never a capability; upgrading clears results stored by earlier releases, so a
   proof consumed before the upgrade cannot be replayed.
3. Store the returned `guest_access_token` only for its stated `expires_at`.
   Send it as `Authorization: Bearer ...`, `X-Guest-Access-Token` or
   `X-Guest-Token` on widget ticket reads/replies, attachment downloads, and the
   API guest ticket read/reply and guest rating routes. Those API and rating
   routes also accept the capability as their `:token` path segment; a header,
   when present, takes precedence over the segment. Ticket and chat capabilities
   are distinct. Changed email, renewal, revocation, expiry or tenant mismatch
   denies an old capability. `GuestAccess.revoke(ticket)` revokes its grants.

The default grant lifetime is one day; `guest_access_ttl_minutes` is clamped to
5–10,080 minutes. Tokens are encrypted and authenticated, with a database nonce,
mailbox hash, purpose, ticket and tenant binding. Legacy permanent `guest_token`
values never authorize access; recipients must prove their mailbox again.
Verified Phoenix submissions currently create an unassigned guest requester
(`requester_id: nil`); the legacy `guest_user` and `prompt_signup` requester
allocation modes are not applied by this flow.

Code delivery has two shared database limits per hour, including failed sends,
across tenants and nodes: `guest_mailbox_ip_limit` (default 3) per mailbox and
client network, and `guest_mailbox_limit` (default 10) per mailbox across every
network. A stranger exhausting one network's budget therefore does not lock the
owner out from theirs, while the global cap still bounds delivery to a mailbox.
IPv6 networks are counted per /64. A refused request spends neither budget.
Service callers of `GuestAccess.challenge/3` should pass `ip: conn.remote_ip`;
without it, calls share one "unknown" network budget. The budget table stores
only keyed hashes of the mailbox (and network), expiry and count; it is
intentionally not a tenant table. The existing IP limits still apply and need a
shared backend on clusters.
Schedule `mix escalated.purge_guest_access` hourly, using the trusted catalog or
`--tenant ID`. It removes at most 1,000 expired challenges and grants per tenant
and 1,000 expired global mailbox buckets per invocation. Active limits and grants
are retained; run it more often if the expired backlog exceeds that batch size.

POST a verified `lookup` proof and `reference` to the matching `/guest/lookup`
or `/widget/lookup` path. Ticket references work directly. The host callback
`guest_reference_resolver.(reference, verified_email, tenant_id)` can map a tracking
number to ticket IDs. Every result is reloaded in the current tenant and checked
against the verified mailbox. The response returns at most 20 ticket summaries
with renewed ticket grants, never unverified lookup results or internal notes.

Chat start returns a capability as `id`/`session_id`. Shared frontend polling uses
`/support/widget/chat/:token/messages` (GET/POST), `/typing`, `/end` and `/rate`.
Legacy reference-based chat paths require the capability header. Message polling,
sending and typing use `widget_chat_rate_limit` rather than the general widget
limit: by default 90 requests a minute per chat capability and network, which
fits a poll and a typing ping every three seconds plus messages, and 300 a minute
per network across capabilities. While `widget_settings.enabled` is false, every
widget route except `/widget/config` answers 403: no codes are sent and no
lookup, ticket or chat traffic is served. The `/guest` and API guest routes are
unaffected. All public grant paths send no-store/no-referrer headers. Configure access-log redaction for token
path segments at the host proxy; the package cannot control upstream logs.

Authenticated API profile/token callbacks require membership before mutation.
Merchant registration requires the explicit `api_tenant_registrar(params, tenant)`
callback and a returned member (directly or under `user`); the legacy global
registrar is not used in merchant mode.

Private attachments require a matching current ticket or chat grant, and exclude
internal-note files. Recipient responses include the latest 100 public replies
and up to 100 visible attachments. Each file link contains a separate encrypted
capability lasting at most five minutes, bound to that file and a still-current
guest grant. Anonymous download attempts share the guest IP limit before
capability decryption. Keep local storage outside static serving. An external
`attachment_download_url` callback receives the shorter of five minutes and the
remaining grant lifetime and must issue a private signed URL for that duration.
Add `verification_code`, `guest_access_token`, `guest_token`, `token` and
`download_token` to host parameter/log redaction. Redact capability path segments
in proxy access logs as well as query parameters.
