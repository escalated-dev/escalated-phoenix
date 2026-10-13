# Ticket access and routing

Existing installations keep their current behavior. The three features are opt-in:

```elixir
config :escalated,
  visibility: :all, # :all | :department
  accounts: %{enabled: false, scope_agents: false, resolver: nil},
  targeted_slas: false,
  access_user_resolver: nil
```

Copy and run `20261013000001_add_ticket_access.exs` with the package migrations before enabling these settings. It adds nullable indexed `account_type` / `account_id` ticket columns, nullable SLA targets and a department membership table. Existing rows and deadlines are preserved. Identity comparisons are case-sensitive on SQLite, PostgreSQL and MySQL. Rollback removes the new data; disable the options first.

## Department visibility

Set `visibility: :department` and populate `Escalated.Schemas.DepartmentAgent` with `department_id` and `agent_id`. Host code owns assigning staff to departments. Memberships live on the package connection, with no foreign key or join to host users. They honor the existing compile-time `table_prefix` and `user_key_type` settings.

Agents can see tickets in their departments. Tickets without a department are hidden from restricted agents. Admins retain access. Account scoping, when enabled, intersects department access. Explicit list filters can only narrow the permitted set. Customer ownership, guest grants and tenant membership remain separate requirements.

`Escalated.repo()` applies the scope across list/search/count/report queries, bulk updates/deletes, child records, both ends of ticket links, mentions, subjects, attachments, side conversations and chat sessions. Package router plugs install the authenticated actor for UI, widget and API requests. A bearer token identifies its owner even when a different session user is present. An agent using a guest widget grant still has that agent's restrictions.

Services, serializers, preloads and repository writes check preloaded records against the stored row. Assignment, automatic assignment, skill routing, chat routing and mentions check eligibility. Bulk changes to ownership or assignment fields are rejected; use individual service operations for those changes. Bulk priority/status updates and deletes are scoped before execution.

Use `Escalated.repo()` for host ticket queries. Direct calls to the host's Ecto repo, `Escalated.storage_repo()`, or raw SQL bypass this facade and are reserved for trusted code. Restricted queries support ordinary package table joins and preloads; unsupported subqueries, CTEs, unions, joined preloads and SQL-prefix overrides are refused. `Escalated.TicketVisibility.assert_record!/1` protects preloaded objects in host services.

Jobs with no actor retain full access. Context is process-local; it does not automatically follow a spawned task. Supply the actor at the job boundary:

```elixir
Escalated.TicketVisibility.with_user(user, fn ->
  Escalated.Services.TicketService.list(%{search: "delivery"})
end)
```

Nested contexts restore after exceptions. `with_user(nil, callback)` is an explicit trusted bypass of department/account restrictions; tenant isolation remains active.

## Accounts

Provide an `accounts.resolver` callback receiving `(kind, type, id)` and returning `%{type: "Company", id: "company-id"}` or `nil`. Kinds are `:requester`, `:subject` and `:agent`. Both identity values must be nonempty and at most 191 bytes; integer IDs are converted to strings. The host owns loading and mapping these references.

With `accounts.enabled: true`, ticket insertion resolves the requester before creation workflows run. Subject attachment fills only an empty account using an atomic compare-and-set in the attachment transaction. A later subject never overwrites an account. Splits inherit the original pair. Public ticket changesets do not mass-assign account fields; trusted host code can explicitly change both columns together.

`accounts.scope_agents: true` restricts each agent to their one resolved account. A missing or incomplete agent pair denies all tickets. Admins bypass this restriction. Use department memberships for agents covering multiple companies.

Lists accept `ticket_type` and complete `account_type` / `account_id` filters. Incomplete account filters match no tickets.

## Rules and SLAs

Workflows, automations and escalation rules accept `ticket_type`, `account_type`, `account_id` and complete `account` conditions. All three engines compare account/type values exactly, including negation. Incomplete account conditions never match.

```json
[
  {"field": "ticket_type", "operator": "equals", "value": "task"},
  {"field": "account", "operator": "equals", "value": {"type": "Company", "id": "company-id"}}
]
```

Supported operators are `equals`, `=`, `==`, `not_equals` and `!=`. Automations also accept `department_id`.

With `targeted_slas: true`, SLA attachment selects the most specific active policy: department plus type, department, type, then an untargeted default. Lowest policy ID wins ties. Configure nullable `department_id` / `ticket_type` policy fields through the service/schema API. The existing SLA enabled setting still controls creation-time attachment.

Moving a ticket preserves its policy and deadlines. Call `SlaService.attach_policy(ticket)` to explicitly reselect. In targeted mode deadlines start at the original ticket creation time, including business-hours calculations. With targeting disabled, existing department-default SLA behavior remains available and untargeted defaults retain their existing behavior.

## Live delivery and notifications

Ticket and chat channels reload authenticated users and recheck ticket access on join and every delivery. Global queue topics filter each event by its ticket. Membership revocation therefore affects already-open sockets. Host PubSub subscribers must perform equivalent authorization before delivering data to clients.

The default identity loader reads `user_schema` through `Escalated.user_repo()`, which can be a separate connection. For another identity store, set `access_user_resolver` to a one-argument callback returning the current user for the requested ID or `nil`. It must return fresh roles; mismatched IDs are refused.

Host notification workers should call `TicketVisibility.recipients(ticket, ids)` immediately before sending. It reloads both identities and ticket ownership. Mention hooks filter recipients before dispatch; queued host hooks must recheck at delivery time too.
