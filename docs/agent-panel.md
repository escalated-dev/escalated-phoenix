# Agent panel data

The shared frontend's agent panel (`@escalated-dev/escalated`, `docs/agent-panel.md`) reads five things this package provides, as escalated-dev/escalated-developer-context ADR `2026-11-05-agent-panel-data` specifies. Run the package migration `20261105000001_add_agent_panel_data` first: it adds `tickets.last_customer_activity_at`, `agent_profiles.chat_status` and the `ticket_reads`, `customer_presence` and `notifications` tables (with your table prefix), on SQLite, PostgreSQL and MySQL.

## Agent status

- `PUT` or `POST {prefix}/agent/status` (`escalated.agent.status`) with `{"status": "online" | "away" | "offline"}` stores the agent's status on their agent profile (`chat_status`; a profile is created if the agent has none). A JSON client gets `{"agent_status": "away"}`; an Inertia visit goes back. Anything else is a 422.
- Staff pages share `escalated.agent_status` (`offline` until set) and `escalated.agent_statuses` (`["online", "away", "offline"]`).
- No permission is needed beyond the agent gate.
- Live chat reads it, as escalated-laravel's chat routing: only `online` agents in a routing rule get new chats (`ChatRoutingService.online_agents/1`) and count towards the widget's chat availability. Away and offline agents, and agents with no profile, are skipped.

## Knowledge base search

- `GET {prefix}/agent/kb/search?q=<2..200 chars>&limit=<1..20, default 10>` (`escalated.agent.kb.search`, `kb.view` under roles & permissions) answers `{"data": [{id, title, excerpt, url, category: {id, name} | null, updated_at}]}`.
- Published articles only; title or body contains the term, case-insensitive, with `%` and `_` taken literally (the customer knowledge base and widget searches now escape them too). Title matches come first, then the most recently updated. `excerpt` is the body as plain text, cut at about 160 characters; `url` is the article's absolute customer knowledge-base URL.
- 404 while the knowledge base is off.

## Unread tickets

- A ticket is unread for an agent when the customer was active on it after the agent last opened it, or when the agent marked it unread. Customer activity is the ticket's creation (not an import) and every public reply from the customer side: the requester, a guest, an inbound email, a chat visitor, or any user who is not staff. Agents' replies, internal notes, system replies and replies a workflow writes are not. Existing tickets have no activity, so none turn unread on upgrade.
- Opening a ticket in the agent panel marks it read. `POST {prefix}/agent/tickets/{reference}/read` and `/unread` (`escalated.agent.tickets.read` / `.unread`) answer `{"is_unread": bool}`; the bulk endpoint takes `mark_read` and `mark_unread` (no value).
- `is_unread` is on every `Agent/TicketIndex` row (one query for the page) and on `Agent/TicketShow`'s ticket (`false`). `inbox.unread` is `{mine, unassigned, all}`, counted with `EXISTS` through the list's own filters and the ticket visibility scope.

## Customer presence

- The customer portal (signed-in customers who are not staff), the guest ticket page and the widget's guest ticket and chat endpoints record when the customer was last seen, at most once every 30 seconds. The subject is the requester, else the ticket's contact, else the ticket itself (a guest chat).
- Agent pages only: each `Agent/TicketIndex` row and `Agent/TicketShow`'s ticket carry `requester_online` (seen within `presence_online_window_seconds`, default 120) and `requester_last_seen_at`. Customer, guest and widget responses never include them.

## Notifications

| Type | Who | When |
|---|---|---|
| `ticket_assigned` | the assignee | someone else assigns them a ticket (assigning yourself sends nothing, email included) |
| `ticket_reply` | the assignee and followers | a public reply from the customer side |
| `mention` | the mentioned agent | an @mention in an internal note |
| `sla_warning` | the assignee | `sla.warning` |
| `sla_breached` | the assignee | `sla.breached` |
| `chat_transferred` | the receiving agent | a chat is transferred to them |

Nobody is notified of their own action.

- `GET {prefix}/agent/notifications?page=&per_page=<1..50, default 20>&unread=1` (`escalated.agent.notifications.index`) answers `{data: [{id, type, title, body, ticket: {id, reference, subject} | null, url, created_at, read_at}], meta: {current_page, last_page, per_page, total}}`, newest first. A notification about a ticket the agent can no longer view is redacted: title "A ticket you can no longer view", `body`, `ticket` and `url` null.
- `POST {prefix}/agent/notifications/{id}/read` answers `{"unread_count": n}` (404 for another agent's notification); `POST {prefix}/agent/notifications/read-all` answers `{"unread_count": 0}`.
- Staff pages share `escalated.notifications.unread_count`.
- With broadcasting on, each new notification is broadcast as `notification.created` (payload: the feed item) on the agent's topic `escalated:agent:<id>`, which `Escalated.Channels.TicketChannel` lets that agent join.
- `config :escalated, agent_notifications: false` switches the feed off: nothing is stored, the routes answer 404 and the shared count is left out.

## Configuration

```elixir
config :escalated,
  # Agent pages show a customer as online when seen within this many seconds.
  presence_online_window_seconds: 120,
  # The agents' in-app notifications feed and bell.
  agent_notifications: true
```
