# Email

## Notification emails

Nothing is emailed until you name a mailer:

```elixir
config :escalated, mailer: MyApp.Mailer, from_email: "support@example.com"
```

Recipients, the delivery-function alternative and threading are in
[notification emails](notification-emails.md).

## Inbound email

Point your Postmark, Mailgun, or AWS SES (via SNS HTTP subscription) inbound webhook at:

```
POST /support/webhook/email/inbound?adapter=postmark
POST /support/webhook/email/inbound?adapter=mailgun
POST /support/webhook/email/inbound?adapter=ses
```

The adapter can be selected via the query parameter or the `x-escalated-adapter` header. Your provider must attach the shared secret as `x-escalated-inbound-secret`, which is compared with `Plug.Crypto.secure_compare/2` (timing-safe).

Configure the symmetric secret + mail domain (used for signed `Reply-To` + canonical `Message-ID` headers) in `config/runtime.exs`:

```elixir
config :escalated,
  mail_domain: System.get_env("ESCALATED_MAIL_DOMAIN", "support.yourapp.com"),
  email_inbound_secret: System.fetch_env!("ESCALATED_INBOUND_SECRET"),
  inbound_parsers: [
    Escalated.Services.Email.Inbound.PostmarkParser,
    Escalated.Services.Email.Inbound.MailgunParser,
    Escalated.Services.Email.Inbound.SESParser
  ]
```

Register the controller route:

```elixir
scope "/support/webhook/email", Escalated.Controllers do
  pipe_through :api
  post "/inbound", InboundEmailController, :inbound
end
```

Outbound notifications carry a signed `Reply-To` (`reply+{id}.{hmac8}@{mail_domain}`). Because the controller requires `email_inbound_secret`, only that signed address links an inbound message to a ticket; `Message-ID` headers and subject-reference tags are guessable and are used only by hosts that call `Escalated.Services.Email.Inbound.Service` directly without a secret.

A linked message becomes a reply only when its `From` address (case-insensitive) is the ticket's requester: the guest email, the requester's Contact email, or the requester user's email. It is posted as that requester, and only such a reply reopens a resolved or closed ticket. Staff identity is never taken from `From`, so agents reply in the app; mail from anyone else, an agent's address included, opens a new ticket instead of being dropped. Lookups use `Escalated.repo/0`, so with tenancy enabled they stay inside the tenant resolved for the webhook request. Have your provider enforce SPF/DKIM/DMARC as well, since `From` itself is unauthenticated.

Unmatched messages with real content create a new ticket; SNS subscription confirmations and empty body+subject messages are skipped.

See the [inbound email docs](https://docs.escalated.dev/inbound-email) for provider setup, the response shape, and a ready-to-paste curl test recipe.
