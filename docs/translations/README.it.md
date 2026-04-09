<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <b>Italiano</b> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.ko.md">한국어</a> •
  <a href="README.nl.md">Nederlands</a> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated per Phoenix

Sistema di helpdesk e ticket di supporto integrabile per applicazioni Phoenix. Ticket di supporto, dipartimenti, politiche SLA e gestione degli agenti pronti all'uso come pacchetto Hex.

## Funzionalità

- **Ciclo di vita del ticket** — Creare, assegnare, rispondere, risolvere, chiudere, riaprire con transizioni di stato configurabili
- **Motore SLA** — Obiettivi di risposta e risoluzione per priorità, calcolo ore lavorative, rilevamento automatico violazioni
- **Dashboard agente** — Coda ticket con filtri, note interne, risposte predefinite
- **Portale cliente** — Creazione ticket self-service, risposte e tracciamento stato
- **Pannello admin** — Gestione dipartimenti, politiche SLA, tag e visualizzazione report
- **Allegati file** — Upload drag-and-drop con storage e limiti dimensione configurabili
- **Timeline attività** — Log di audit completo di ogni azione su ogni ticket
- **Routing dipartimentale** — Organizzare agenti in dipartimenti con assegnazione automatica
- **Sistema di tag** — Categorizzare ticket con tag colorati
- **Divisione ticket** — Dividere una risposta in un nuovo ticket indipendente preservando il contesto originale
- **Posticipo ticket** — Posticipare ticket con preset (1h, 4h, domani, prossima settimana); il task `mix escalated.wake_snoozed_tickets` li risveglia automaticamente secondo il programma
- **Viste salvate / code personalizzate** — Salvare, nominare e condividere preset di filtri come viste ticket riutilizzabili
- **Widget di supporto integrabile** — Widget `<script>` leggero con ricerca KB, modulo ticket e verifica stato
- **Threading email** — Le email in uscita includono header `In-Reply-To` e `References` corretti per il threading appropriato nei client di posta
- **Template email personalizzati** — Logo configurabile, colore primario e testo footer per tutte le email in uscita
- **Broadcasting in tempo reale** — Broadcasting opt-in tramite Phoenix PubSub con polling automatico di fallback
- **Toggle knowledge base** — Abilitare o disabilitare la knowledge base pubblica dalle impostazioni admin

## Installazione

Aggiungi `escalated` alla tua lista di dipendenze in `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Configurazione

Aggiungi quanto segue al tuo `config/config.exs`:

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

### Opzioni di configurazione

| Opzione | Predefinito | Descrizione |
|--------|---------|-------------|
| `repo` | *richiesto* | Il tuo modulo Ecto Repo |
| `user_schema` | *richiesto* | Il tuo modulo schema User |
| `route_prefix` | `"/support"` | Prefisso URL per tutte le route Escalated |
| `table_prefix` | `"escalated_"` | Prefisso nomi tabelle database |
| `ui_enabled` | `true` | Monta route UI Inertia.js |
| `api_enabled` | `false` | Monta route JSON API |
| `admin_check` | `nil` | Funzione `(user -> boolean)` per accesso admin |
| `agent_check` | `nil` | Funzione `(user -> boolean)` per accesso agente |
| `default_priority` | `:medium` | Priorità ticket predefinita |
| `allow_customer_close` | `true` | Consenti ai clienti di chiudere i propri ticket |
| `sla` | `%{enabled: true, ...}` | Mappa configurazione SLA |

## Setup del database

Esegui la migrazione Escalated:

```bash
mix ecto.gen.migration create_escalated_tables
```

Poi copia il contenuto della migrazione da `priv/repo/migrations/20260406000001_create_escalated_tables.exs` o installa tramite:

```bash
mix ecto.migrate
```

## Setup del router

Monta le route Escalated nel tuo router Phoenix:

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

Questo monta:

- **Route cliente** su `/support/tickets/*` — visualizzare/creare/rispondere ai ticket
- **Route agente** su `/support/agent/*` — dashboard agente e gestione ticket
- **Route admin** su `/support/admin/*` — amministrazione completa (dipartimenti, tag, impostazioni)
- **Route API** su `/support/api/v1/*` — JSON API (quando `api_enabled: true`)

## Utilizzo

### Creare ticket programmaticamente

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Rispondere ai ticket

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Assegnare ticket

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### Gestione SLA

```elixir
# Controllare le violazioni SLA (eseguire periodicamente tramite scheduler)
breached = Escalated.Services.SlaService.check_breaches()

# Ottenere statistiche SLA
stats = Escalated.Services.SlaService.stats()
```

## Rendering dell'interfaccia

Per impostazione predefinita, Escalated renderizza le pagine tramite [Inertia.js](https://github.com/inertiajs/inertia-phoenix) quando `inertia_phoenix` è installato. Se Inertia non è disponibile, i controller ricadono sulle risposte JSON.

Puoi costruire i tuoi componenti frontend che consumano le props della pagina Inertia, o usare direttamente la JSON API.

## Plugs

Escalated fornisce plug per l'autorizzazione:

- `Escalated.Plugs.EnsureAgent` — richiede che l'utente superi il `agent_check` configurato
- `Escalated.Plugs.EnsureAdmin` — richiede che l'utente superi il `admin_check` configurato
- `Escalated.Plugs.ShareInertiaData` — condivide i dati comuni di Escalated con le pagine Inertia

## Schemi

- `Escalated.Schemas.Ticket` — ticket di supporto con stato, priorità, tracciamento SLA
- `Escalated.Schemas.Reply` — risposte ai ticket e note interne
- `Escalated.Schemas.Department` — dipartimenti/team di supporto
- `Escalated.Schemas.Tag` — tag dei ticket per la categorizzazione
- `Escalated.Schemas.SlaPolicy` — politiche SLA con obiettivi per priorità
- `Escalated.Schemas.TicketActivity` — log di audit delle modifiche ai ticket
- `Escalated.Schemas.AgentProfile` — dati del profilo specifici dell'agente

## Licenza

Licenza MIT. Vedi [LICENSE](LICENSE) per i dettagli.
