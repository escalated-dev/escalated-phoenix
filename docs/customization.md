# Customization

## Ticket subjects

A ticket has a **requester** (who raised it) and a **subject line** (free text). Tickets can also be *about* host-app entities — a Project, Customer, asset — that are not people. Attach them as ticket **subjects** so agents see what the ticket concerns and can jump into your app.

Implement the `Escalated.TicketSubject` behaviour on any host struct and register a resolver:

```elixir
defmodule MyApp.Projects.Project do
  @behaviour Escalated.TicketSubject

  def ticket_subject_title(project), do: project.name
  def ticket_subject_subtitle(project), do: "Project · #{project.account}"
  def ticket_subject_url(project), do: Routes.project_url(MyAppWeb.Endpoint, :show, project)
  def ticket_subject_color(_), do: "#2563eb"
  def ticket_subject_icon(_), do: "folder"
end

# config/config.exs
config :escalated,
  ticket_subjects: [
    types: ["project", "customer"],
    resolver: &MyApp.TicketSubjects.resolve/2
  ]
```

Attach, detach, or sync from application code:

```elixir
Escalated.Services.TicketSubjectService.attach_subject(ticket, "project", "prj_9f1c", role: "project")
Escalated.Services.TicketSubjectService.detach_subject(ticket, "project", "prj_9f1c")
Escalated.Services.TicketSubjectService.sync_subjects(ticket, [{"project", "b", "primary"}, {"customer", "c"}])
```

Each link is serialized on ticket detail JSON as
`{ type, id, role, title, subtitle, url, color, icon, missing }`.
Admin routes `POST` / `DELETE` … `/admin/tickets/:reference/subjects` accept only allowlisted types and require the resolver to return a struct.

`subject_id` is stored as a string (not `Escalated.UserKey`) so integer, UUID, and custom string host keys all work.

## Custom Ticket Actions

Host applications can add custom buttons to the agent ticket screen and react to
clicks by subscribing to the broadcast event. Register actions under the
`:custom_actions` config key:

```elixir
config :escalated,
  custom_actions: [
    %{
      key: "sync-crm",
      label: "Sync CRM",
      variant: "primary",
      confirmation: "Sync this ticket to the CRM?",
      metadata: %{icon: "refresh-cw"},
      # visible / enabled may be a boolean or fn(ticket, user) -> boolean
      enabled: fn ticket, _user -> ticket.status in ["open", "in_progress"] end
    }
  ]
```

Visible actions are exposed on the agent ticket show as `customActions` and on
the API ticket detail response as `custom_actions` (each with a `url` and
`method`). Triggering one (`POST /support/agent/tickets/:reference/actions/:action`
or the API equivalent) validates the action is visible (404) and enabled (403),
records an internal note for auditability, and broadcasts
`ticket:custom_action_triggered`:

```elixir
Escalated.Broadcasting.subscribe_ticket(ticket_id)

# In your LiveView / GenServer handle_info:
def handle_info(%{event: "ticket:custom_action_triggered", payload: payload}, socket) do
  # payload.action, payload.user_id, payload.payload, payload.metadata
  {:noreply, socket}
end
```

## Usage

### Creating Tickets Programmatically

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Replying to Tickets

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Assigning Tickets

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA Management

```elixir
# Check for SLA breaches (dispatches sla.breached) and deadlines due within
# 30 minutes (dispatches sla.warning). Run both periodically via a scheduler,
# or run `mix escalated.check_sla`, which does exactly this.
breached = Escalated.Services.SlaService.check_breaches()
warned = Escalated.Services.SlaService.check_warnings(30)

# Get SLA statistics
stats = Escalated.Services.SlaService.stats()
```

## Translations

Escalated for Phoenix consumes its translation catalogs from the central
[`:escalated_locale`](https://hex.pm/packages/escalated_locale) Hex package
so that every Escalated host plugin (Phoenix, Laravel, Rails, Django, …)
ships an identical message set.

The central package exposes Gettext-style `.po` files at
`priv/gettext/{locale}/LC_MESSAGES/escalated.po`. This repository defines an
`Escalated.Gettext` backend that re-exports those catalogs and additionally
loads any per-host overrides placed under
`priv/gettext/overrides/{locale}/LC_MESSAGES/escalated.po`.

Override pattern:

```
priv/gettext/overrides/
└── en/
    └── LC_MESSAGES/
        └── escalated.po   # only the strings you want to differ from upstream
```

Translation contributions should be opened against
[`escalated-dev/escalated-locale`](https://github.com/escalated-dev/escalated-locale),
not this repository — that way every host plugin picks the change up on the
next `mix deps.update escalated_locale`.
