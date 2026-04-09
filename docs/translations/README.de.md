<p align="center">
  <a href="README.ar.md">العربية</a> •
  <b>Deutsch</b> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.ko.md">한국어</a> •
  <a href="README.nl.md">Nederlands</a> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated für Phoenix

Einbettbares Helpdesk- und Support-Ticketsystem für Phoenix-Anwendungen. Sofort einsatzbereite Support-Tickets, Abteilungen, SLA-Richtlinien und Agentenverwaltung als Hex-Paket.

## Funktionen

- **Ticket-Lebenszyklus** — Erstellen, Zuweisen, Antworten, Lösen, Schließen, Wiederöffnen mit konfigurierbaren Statusübergängen
- **SLA-Engine** — Antwort- und Lösungsziele pro Priorität, Geschäftszeitenberechnung, automatische Verletzungserkennung
- **Agenten-Dashboard** — Ticket-Warteschlange mit Filtern, internen Notizen, vorgefertigten Antworten
- **Kundenportal** — Self-Service-Ticketerstellung, Antworten und Statusverfolgung
- **Admin-Panel** — Verwaltung von Abteilungen, SLA-Richtlinien, Tags und Berichten
- **Dateianhänge** — Drag-and-Drop-Uploads mit konfigurierbarem Speicher und Größenlimits
- **Aktivitätszeitlinie** — Vollständiges Audit-Log jeder Aktion an jedem Ticket
- **Abteilungsrouting** — Agenten in Abteilungen organisieren mit automatischer Zuweisung
- **Tagging-System** — Tickets mit farbigen Tags kategorisieren
- **Ticket-Aufteilung** — Eine Antwort in ein neues eigenständiges Ticket aufteilen und dabei den ursprünglichen Kontext bewahren
- **Ticket-Schlummern** — Tickets mit Voreinstellungen schlummern lassen (1 Std., 4 Std., morgen, nächste Woche); `mix escalated.wake_snoozed_tickets` Mix-Task weckt sie planmäßig automatisch
- **Gespeicherte Ansichten / benutzerdefinierte Warteschlangen** — Filter-Voreinstellungen als wiederverwendbare Ticket-Ansichten speichern, benennen und teilen
- **Einbettbares Support-Widget** — Leichtgewichtiges `<script>`-Widget mit KB-Suche, Ticketformular und Statusprüfung
- **E-Mail-Threading** — Ausgehende E-Mails enthalten korrekte `In-Reply-To`- und `References`-Header für korrektes Threading in E-Mail-Clients
- **Gebrandete E-Mail-Vorlagen** — Konfigurierbares Logo, Primärfarbe und Fußzeilentext für alle ausgehenden E-Mails
- **Echtzeit-Broadcasting** — Opt-in-Broadcasting über Phoenix PubSub mit automatischem Polling-Fallback
- **Wissensdatenbank-Umschalter** — Öffentliche Wissensdatenbank in den Admin-Einstellungen aktivieren oder deaktivieren

## Installation

Fügen Sie `escalated` zu Ihrer Abhängigkeitsliste in `mix.exs` hinzu:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Konfiguration

Fügen Sie Folgendes zu Ihrer `config/config.exs` hinzu:

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

### Konfigurationsoptionen

| Option | Standard | Beschreibung |
|--------|---------|-------------|
| `repo` | *erforderlich* | Ihr Ecto-Repo-Modul |
| `user_schema` | *erforderlich* | Ihr User-Schema-Modul |
| `route_prefix` | `"/support"` | URL-Präfix für alle Escalated-Routen |
| `table_prefix` | `"escalated_"` | Präfix für Datenbanktabellennamen |
| `ui_enabled` | `true` | Inertia.js-UI-Routen einbinden |
| `api_enabled` | `false` | JSON-API-Routen einbinden |
| `admin_check` | `nil` | Funktion `(user -> boolean)` für Admin-Zugang |
| `agent_check` | `nil` | Funktion `(user -> boolean)` für Agenten-Zugang |
| `default_priority` | `:medium` | Standard-Ticketpriorität |
| `allow_customer_close` | `true` | Kunden erlauben, ihre Tickets zu schließen |
| `sla` | `%{enabled: true, ...}` | SLA-Konfigurationsmap |

## Datenbank-Setup

Führen Sie die Escalated-Migration aus:

```bash
mix ecto.gen.migration create_escalated_tables
```

Kopieren Sie dann den Migrationsinhalt aus `priv/repo/migrations/20260406000001_create_escalated_tables.exs` oder installieren Sie über:

```bash
mix ecto.migrate
```

## Router-Setup

Binden Sie Escalated-Routen in Ihren Phoenix-Router ein:

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

Dies bindet ein:

- **Kundenrouten** unter `/support/tickets/*` — Tickets anzeigen/erstellen/beantworten
- **Agentenrouten** unter `/support/agent/*` — Agenten-Dashboard und Ticketverwaltung
- **Admin-Routen** unter `/support/admin/*` — Vollständige Verwaltung (Abteilungen, Tags, Einstellungen)
- **API-Routen** unter `/support/api/v1/*` — JSON-API (wenn `api_enabled: true`)

## Verwendung

### Tickets programmatisch erstellen

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Auf Tickets antworten

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Tickets zuweisen

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA-Verwaltung

```elixir
# Auf SLA-Verletzungen prüfen (periodisch über einen Scheduler ausführen)
breached = Escalated.Services.SlaService.check_breaches()

# SLA-Statistiken abrufen
stats = Escalated.Services.SlaService.stats()
```

## UI-Rendering

Standardmäßig rendert Escalated Seiten über [Inertia.js](https://github.com/inertiajs/inertia-phoenix), wenn `inertia_phoenix` installiert ist. Wenn Inertia nicht verfügbar ist, fallen Controller auf JSON-Antworten zurück.

Sie können eigene Frontend-Komponenten erstellen, die die Inertia-Seitenprops konsumieren, oder die JSON-API direkt verwenden.

## Plugs

Escalated bietet Plugs für die Autorisierung:

- `Escalated.Plugs.EnsureAgent` — erfordert, dass der Benutzer den konfigurierten `agent_check` besteht
- `Escalated.Plugs.EnsureAdmin` — erfordert, dass der Benutzer den konfigurierten `admin_check` besteht
- `Escalated.Plugs.ShareInertiaData` — teilt gemeinsame Escalated-Daten mit Inertia-Seiten

## Schemata

- `Escalated.Schemas.Ticket` — Support-Tickets mit Status, Priorität, SLA-Tracking
- `Escalated.Schemas.Reply` — Ticket-Antworten und interne Notizen
- `Escalated.Schemas.Department` — Support-Abteilungen/Teams
- `Escalated.Schemas.Tag` — Ticket-Tags zur Kategorisierung
- `Escalated.Schemas.SlaPolicy` — SLA-Richtlinien mit prioritätsbezogenen Zielen
- `Escalated.Schemas.TicketActivity` — Audit-Log von Ticket-Änderungen
- `Escalated.Schemas.AgentProfile` — Agentenspezifische Profildaten

## Lizenz

MIT-Lizenz. Siehe [LICENSE](LICENSE) für Details.
