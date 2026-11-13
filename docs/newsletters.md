# Newsletters

## Newsletters (optional, partial port)

Schema, schemas, and renderer for the admin-only newsletter broadcast feature. Off by default — host integrators flip `:newsletter_tracking_enabled` and other application env values to configure behavior. The DB-bound planner / dispatcher / tracker services need integration with the host's Repo layer and ship as a follow-up.

```elixir
# config/config.exs
config :escalated,
  app_url: "https://support.example.com",
  newsletter_default_theme: "default",
  newsletter_tracking_enabled: true,
  newsletter_brand_accent: "#2563eb",
  newsletter_brand_physical_address: "Acme Inc. · 123 Main St",
  newsletter_markdown_renderer: &Earmark.as_html!/1
```

```elixir
alias Escalated.Services.Newsletter.Renderer

html = Renderer.render(delivery, newsletter, contact, template_or_nil)
```

The package ships:
- `priv/repo/migrations/20260522000001_create_newsletter_system.exs` — Ecto migration
- `lib/escalated/schemas/newsletter/*.ex` — 5 Ecto schemas
- `lib/escalated/services/newsletter/renderer.ex` — full renderer
- `priv/templates/newsletter_themes/{default,branded}.html.eex` — starter themes

Follow-up PR: planner / dispatcher / tracker services using the host's Repo, plus router controllers.
