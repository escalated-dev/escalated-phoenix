# Notification emails

Escalated emails requesters and agents when something happens on a ticket. It
sends through your application's mailer, and sends nothing until you configure
one.

## Setup

Point Escalated at a Swoosh mailer (the one `mix phx.new` generates works):

```elixir
config :escalated,
  mailer: MyApp.Mailer,
  from_email: "support@example.com",
  email_domain: "support.example.com",
  email_branding: %{
    company_name: "Acme Support",
    logo_url: "https://example.com/logo.png",
    accent_color: "#4F46E5",
    footer_text: "Acme Inc."
  }
```

Escalated builds a `%Swoosh.Email{}` and calls `MyApp.Mailer.deliver/1`. Swoosh
stays your dependency; Escalated does not add it.

To send some other way, give a one-argument function instead. It receives a map
with `:to`, `:from` (`{name, address}`), `:subject`, `:headers`, `:reply_to`,
`:html_body` and `:text_body`:

```elixir
config :escalated, notification_delivery: &MyApp.SupportMail.deliver/1
```

Email goes out only while `:notification_channels` includes `:email`, which is
the default. Set `notification_channels: []` to turn it off without removing
the mailer.

Delivery runs in its own process, so a slow mail server does not hold up the
request. `config :escalated, notification_sync: true` sends inline, which is
useful in tests. A mailer error is logged and never fails the ticket operation.

## Who gets what

The rules follow escalated-laravel.

| Event | Recipients |
|---|---|
| Ticket created | The requester (the first message of the thread), and the assignee if the ticket was created assigned |
| Public reply | The requester unless they wrote it; the assignee unless they wrote it; followers other than the author, requester and assignee |
| Ticket assigned | The new assignee |
| Status changed | The requester and the followers, except whoever changed it |
| Ticket escalated | The assignee |
| SLA breached | The assignee |

Internal notes and live chat messages email nobody. Nobody is emailed about
their own action.

Agents are your host users, looked up by id through `:user_schema` (its
`email` field) on `Escalated.user_repo/0`. When ticket visibility is
restricted, agents who cannot see the ticket are skipped
(`Escalated.TicketVisibility.recipients/2`). The requester is the host user for
a user ticket, or the guest address (falling back to the ticket's contact) for
a guest ticket.

## Threading

Every message carries the headers in `Escalated.Emails.TicketEmail`:

- the new-ticket email sets `Message-ID: <ticket-{id}@{email_domain}>`, the
  anchor of the thread;
- a reply email sets its own `Message-ID: <ticket-{id}-reply-{reply_id}@{email_domain}>`
  and `In-Reply-To` / `References` pointing at the anchor;
- assignment, status, escalation and SLA emails set `In-Reply-To` /
  `References` to the anchor.

When `:email_inbound_secret` is set, each message also has a signed
`Reply-To` (`reply+{id}.{hmac8}@{email_domain}`), so a reply by email threads
back onto the ticket through the [inbound endpoint](../README.md#inbound-email).
