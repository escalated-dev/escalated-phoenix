<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.ko.md">한국어</a> •
  <a href="README.nl.md">Nederlands</a> •
  <b>Polski</b> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated dla Phoenix

Wbudowany system helpdesk i zgłoszeń wsparcia dla aplikacji Phoenix. Gotowe do użycia zgłoszenia wsparcia, działy, polityki SLA i zarządzanie agentami jako pakiet Hex.

## Funkcje

- **Cykl życia zgłoszenia** — Tworzenie, przypisywanie, odpowiadanie, rozwiązywanie, zamykanie, ponowne otwieranie z konfigurowalnymi przejściami statusów
- **Silnik SLA** — Cele odpowiedzi i rozwiązania na priorytet, obliczanie godzin pracy, automatyczne wykrywanie naruszeń
- **Panel agenta** — Kolejka zgłoszeń z filtrami, notatkami wewnętrznymi, gotowymi odpowiedziami
- **Portal klienta** — Samoobsługowe tworzenie zgłoszeń, odpowiedzi i śledzenie statusu
- **Panel administracyjny** — Zarządzanie działami, politykami SLA, tagami i przeglądanie raportów
- **Załączniki plików** — Przesyłanie metodą przeciągnij i upuść z konfigurowalnym magazynem i limitami rozmiaru
- **Oś czasu aktywności** — Pełny dziennik audytu każdej akcji na każdym zgłoszeniu
- **Routing departamentowy** — Organizacja agentów w działy z automatycznym przypisywaniem
- **System tagów** — Kategoryzacja zgłoszeń kolorowymi tagami
- **Podział zgłoszeń** — Podział odpowiedzi na nowe samodzielne zgłoszenie z zachowaniem oryginalnego kontekstu
- **Wstrzymywanie zgłoszeń** — Wstrzymywanie zgłoszeń z predefiniowanymi ustawieniami (1h, 4h, jutro, przyszły tydzień); zadanie `mix escalated.wake_snoozed_tickets` automatycznie je budzi zgodnie z harmonogramem
- **Zapisane widoki / kolejki niestandardowe** — Zapisywanie, nazywanie i udostępnianie presetów filtrów jako wielokrotnego użytku widoków zgłoszeń
- **Wbudowany widget wsparcia** — Lekki widget `<script>` z wyszukiwaniem bazy wiedzy, formularzem zgłoszenia i sprawdzaniem statusu
- **Wątkowanie e-maili** — Wychodzące e-maile zawierają prawidłowe nagłówki `In-Reply-To` i `References` dla poprawnego wątkowania w klientach poczty
- **Markowe szablony e-maili** — Konfigurowalne logo, kolor główny i tekst stopki dla wszystkich wychodzących e-maili
- **Nadawanie w czasie rzeczywistym** — Opcjonalne nadawanie przez Phoenix PubSub z automatycznym odpytywaniem jako rezerwą
- **Przełącznik bazy wiedzy** — Włączanie lub wyłączanie publicznej bazy wiedzy z ustawień administracyjnych

## Instalacja

Dodaj `escalated` do listy zależności w `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Konfiguracja

Dodaj poniższe do `config/config.exs`:

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

### Opcje konfiguracji

| Opcja | Domyślnie | Opis |
|--------|---------|-------------|
| `repo` | *wymagane* | Moduł Ecto Repo |
| `user_schema` | *wymagane* | Moduł schematu User |
| `route_prefix` | `"/support"` | Prefiks URL dla wszystkich tras Escalated |
| `table_prefix` | `"escalated_"` | Prefiks nazw tabel bazy danych |
| `ui_enabled` | `true` | Montowanie tras interfejsu Inertia.js |
| `api_enabled` | `false` | Montowanie tras JSON API |
| `admin_check` | `nil` | Funkcja `(user -> boolean)` dla dostępu administratora |
| `agent_check` | `nil` | Funkcja `(user -> boolean)` dla dostępu agenta |
| `default_priority` | `:medium` | Domyślny priorytet zgłoszenia |
| `allow_customer_close` | `true` | Pozwalanie klientom zamykać swoje zgłoszenia |
| `sla` | `%{enabled: true, ...}` | Mapa konfiguracji SLA |

## Konfiguracja bazy danych

Uruchom migrację Escalated:

```bash
mix ecto.gen.migration create_escalated_tables
```

Następnie skopiuj zawartość migracji z `priv/repo/migrations/20260406000001_create_escalated_tables.exs` lub zainstaluj przez:

```bash
mix ecto.migrate
```

## Konfiguracja routera

Zamontuj trasy Escalated w routerze Phoenix:

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

To montuje:

- **Trasy klienta** pod `/support/tickets/*` — przeglądanie/tworzenie/odpowiadanie na zgłoszenia
- **Trasy agenta** pod `/support/agent/*` — panel agenta i zarządzanie zgłoszeniami
- **Trasy administratora** pod `/support/admin/*` — pełna administracja (działy, tagi, ustawienia)
- **Trasy API** pod `/support/api/v1/*` — JSON API (gdy `api_enabled: true`)

## Użycie

### Programowe tworzenie zgłoszeń

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Odpowiadanie na zgłoszenia

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Przypisywanie zgłoszeń

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### Zarządzanie SLA

```elixir
# Sprawdzanie naruszeń SLA (uruchamiać okresowo przez planistę)
breached = Escalated.Services.SlaService.check_breaches()

# Pobieranie statystyk SLA
stats = Escalated.Services.SlaService.stats()
```

## Renderowanie interfejsu

Domyślnie Escalated renderuje strony przez [Inertia.js](https://github.com/inertiajs/inertia-phoenix) gdy `inertia_phoenix` jest zainstalowane. Jeśli Inertia nie jest dostępne, kontrolery przechodzą na odpowiedzi JSON.

Możesz zbudować własne komponenty frontendowe korzystające z propsów strony Inertia lub bezpośrednio używać JSON API.

## Plugi

Escalated udostępnia plugi do autoryzacji:

- `Escalated.Plugs.EnsureAgent` — wymaga przejścia skonfigurowanego `agent_check` przez użytkownika
- `Escalated.Plugs.EnsureAdmin` — wymaga przejścia skonfigurowanego `admin_check` przez użytkownika
- `Escalated.Plugs.ShareInertiaData` — udostępnia wspólne dane Escalated stronom Inertia

## Schematy

- `Escalated.Schemas.Ticket` — zgłoszenia wsparcia ze statusem, priorytetem, śledzeniem SLA
- `Escalated.Schemas.Reply` — odpowiedzi na zgłoszenia i notatki wewnętrzne
- `Escalated.Schemas.Department` — działy/zespoły wsparcia
- `Escalated.Schemas.Tag` — tagi zgłoszeń do kategoryzacji
- `Escalated.Schemas.SlaPolicy` — polityki SLA z celami na priorytet
- `Escalated.Schemas.TicketActivity` — dziennik audytu zmian zgłoszeń
- `Escalated.Schemas.AgentProfile` — dane profilu specyficzne dla agenta

## Licencja

Licencja MIT. Zobacz [LICENSE](LICENSE) po szczegóły.
