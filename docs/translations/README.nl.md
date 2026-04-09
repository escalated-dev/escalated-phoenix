<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.ko.md">한국어</a> •
  <b>Nederlands</b> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated voor Phoenix

Inbedbaar helpdesk- en support-ticketsysteem voor Phoenix-applicaties. Kant-en-klare support-tickets, afdelingen, SLA-beleid en agentbeheer als Hex-pakket.

## Functies

- **Ticket-levenscyclus** — Aanmaken, toewijzen, beantwoorden, oplossen, sluiten, heropenen met configureerbare statusovergangen
- **SLA-engine** — Respons- en oplossingsdoelen per prioriteit, kantooruurberekening, automatische overtredingsdetectie
- **Agentdashboard** — Ticketwachtrij met filters, interne notities, standaardantwoorden
- **Klantenportaal** — Self-service ticketaanmaak, antwoorden en statusopvolging
- **Adminpaneel** — Beheer afdelingen, SLA-beleid, tags en bekijk rapporten
- **Bestandsbijlagen** — Drag-and-drop uploads met configureerbare opslag en groottelimieten
- **Activiteitstijdlijn** — Volledige auditlog van elke actie op elk ticket
- **Afdelingsroutering** — Agenten organiseren in afdelingen met automatische toewijzing
- **Tagsysteem** — Tickets categoriseren met gekleurde tags
- **Ticket splitsen** — Een antwoord afsplitsen naar een nieuw zelfstandig ticket met behoud van de oorspronkelijke context
- **Ticket snoozen** — Tickets snoozen met voorinstellingen (1u, 4u, morgen, volgende week); `mix escalated.wake_snoozed_tickets` Mix-taak wekt ze automatisch volgens schema
- **Opgeslagen weergaven / aangepaste wachtrijen** — Filtervoorinstellingen opslaan, benoemen en delen als herbruikbare ticketweergaven
- **Inbedbare supportwidget** — Lichtgewicht `<script>`-widget met KB-zoeken, ticketformulier en statuscontrole
- **E-mailthreading** — Uitgaande e-mails bevatten correcte `In-Reply-To`- en `References`-headers voor correcte threading in e-mailclients
- **Gepersonaliseerde e-mailsjablonen** — Configureerbaar logo, primaire kleur en voettekst voor alle uitgaande e-mails
- **Realtime broadcasting** — Opt-in broadcasting via Phoenix PubSub met automatische polling-fallback
- **Kennisbank-schakelaar** — Publieke kennisbank in-/uitschakelen vanuit de admin-instellingen

## Installatie

Voeg `escalated` toe aan uw lijst met afhankelijkheden in `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Configuratie

Voeg het volgende toe aan uw `config/config.exs`:

```elixir
config :escalated,
  repo: MyApp.Repo,
  user_schema: MyApp.Accounts.User,
  route_prefix: "/support",
  table_prefix: "escalated_",
  ui_enabled: true,
  admin_check: &MyApp.Accounts.admin?/1,
  agent_check: &MyApp.Accounts.agent?/1
```

### Configuratieopties

| Optie | Standaard | Beschrijving |
|--------|---------|-------------|
| `repo` | *vereist* | Uw Ecto Repo-module |
| `user_schema` | *vereist* | Uw User-schemamodule |
| `route_prefix` | `"/support"` | URL-prefix voor alle Escalated-routes |
| `table_prefix` | `"escalated_"` | Prefix voor databasetabelnamen |
| `ui_enabled` | `true` | Inertia.js UI-routes koppelen |
| `api_enabled` | `false` | JSON API-routes koppelen |
| `admin_check` | `nil` | Functie `(user -> boolean)` voor admintoegang |
| `agent_check` | `nil` | Functie `(user -> boolean)` voor agenttoegang |
| `default_priority` | `:medium` | Standaard ticketprioriteit |
| `allow_customer_close` | `true` | Klanten toestaan hun tickets te sluiten |
| `sla` | `%{enabled: true, ...}` | SLA-configuratiemap |

## Database-setup

Voer de Escalated-migratie uit:

```bash
mix ecto.gen.migration create_escalated_tables
```

Kopieer vervolgens de migratie-inhoud van `priv/repo/migrations/20260406000001_create_escalated_tables.exs` of installeer via:

```bash
mix ecto.migrate
```

## Router-setup

Koppel Escalated-routes in uw Phoenix-router:

```elixir
defmodule MyAppWeb.Router do
  use MyAppWeb, :router
  use Escalated.Router

  pipeline :authenticated do
    plug :require_authenticated_user
  end

  scope "/" do
    pipe_through [:browser, :authenticated]
    escalated_routes("/support")
  end
end
```

Dit koppelt:

- **Klantroutes** op `/support/tickets/*` — tickets bekijken/aanmaken/beantwoorden
- **Agentroutes** op `/support/agent/*` — agentdashboard en ticketbeheer
- **Adminroutes** op `/support/admin/*` — volledige administratie (afdelingen, tags, instellingen)
- **API-routes** op `/support/api/v1/*` — JSON API (wanneer `api_enabled: true`)

## Gebruik

### Tickets programmatisch aanmaken

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Op tickets antwoorden

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Tickets toewijzen

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA-beheer

```elixir
# Controleren op SLA-overtredingen (periodiek uitvoeren via een planner)
breached = Escalated.Services.SlaService.check_breaches()

# SLA-statistieken ophalen
stats = Escalated.Services.SlaService.stats()
```

## UI-rendering

Standaard rendert Escalated pagina's via [Inertia.js](https://github.com/inertiajs/inertia-phoenix) wanneer `inertia_phoenix` is geïnstalleerd. Als Inertia niet beschikbaar is, vallen controllers terug op JSON-responses.

U kunt uw eigen frontendcomponenten bouwen die de Inertia-paginaprops gebruiken, of de JSON API direct aanspreken.

## Plugs

Escalated biedt plugs voor autorisatie:

- `Escalated.Plugs.EnsureAgent` — vereist dat de gebruiker de geconfigureerde `agent_check` doorstaat
- `Escalated.Plugs.EnsureAdmin` — vereist dat de gebruiker de geconfigureerde `admin_check` doorstaat
- `Escalated.Plugs.ShareInertiaData` — deelt gemeenschappelijke Escalated-gegevens met Inertia-pagina's

## Schema's

- `Escalated.Schemas.Ticket` — supporttickets met status, prioriteit, SLA-tracking
- `Escalated.Schemas.Reply` — ticketantwoorden en interne notities
- `Escalated.Schemas.Department` — support-afdelingen/teams
- `Escalated.Schemas.Tag` — tickettags voor categorisering
- `Escalated.Schemas.SlaPolicy` — SLA-beleid met doelen per prioriteit
- `Escalated.Schemas.TicketActivity` — auditlog van ticketwijzigingen
- `Escalated.Schemas.AgentProfile` — agentspecifieke profielgegevens

## Licentie

MIT-licentie. Zie [LICENSE](LICENSE) voor details.
