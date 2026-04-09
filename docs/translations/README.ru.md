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
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <b>Русский</b> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated для Phoenix

Встраиваемая система поддержки и тикетов для приложений Phoenix. Готовые тикеты поддержки, отделы, политики SLA и управление агентами в виде пакета Hex.

## Возможности

- **Жизненный цикл тикета** — Создание, назначение, ответ, решение, закрытие, переоткрытие с настраиваемыми переходами статусов
- **Движок SLA** — Цели по времени ответа и решения для каждого приоритета, расчёт рабочих часов, автоматическое обнаружение нарушений
- **Панель агента** — Очередь тикетов с фильтрами, внутренними заметками, готовыми ответами
- **Портал клиента** — Самообслуживание: создание тикетов, ответы и отслеживание статуса
- **Панель администратора** — Управление отделами, политиками SLA, тегами и просмотр отчётов
- **Файловые вложения** — Загрузка перетаскиванием с настраиваемым хранилищем и лимитами размера
- **Хронология активности** — Полный журнал аудита каждого действия по каждому тикету
- **Маршрутизация по отделам** — Организация агентов в отделы с автоматическим назначением
- **Система тегов** — Категоризация тикетов цветными тегами
- **Разделение тикетов** — Разделение ответа в новый самостоятельный тикет с сохранением исходного контекста
- **Откладывание тикетов** — Откладывание тикетов с пресетами (1ч, 4ч, завтра, следующая неделя); задача `mix escalated.wake_snoozed_tickets` автоматически пробуждает их по расписанию
- **Сохранённые представления / пользовательские очереди** — Сохранение, именование и совместное использование пресетов фильтров как повторно используемых представлений тикетов
- **Встраиваемый виджет поддержки** — Лёгкий виджет `<script>` с поиском по базе знаний, формой тикета и проверкой статуса
- **Потоковая обработка электронной почты** — Исходящие письма включают правильные заголовки `In-Reply-To` и `References` для корректной группировки в почтовых клиентах
- **Брендированные шаблоны писем** — Настраиваемый логотип, основной цвет и текст подвала для всех исходящих писем
- **Трансляция в реальном времени** — Опциональная трансляция через Phoenix PubSub с автоматическим откатом на опрос
- **Переключатель базы знаний** — Включение или отключение публичной базы знаний из настроек администратора

## Установка

Добавьте `escalated` в список зависимостей в `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Конфигурация

Добавьте следующее в ваш `config/config.exs`:

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

### Параметры конфигурации

| Параметр | По умолчанию | Описание |
|--------|---------|-------------|
| `repo` | *обязательно* | Ваш модуль Ecto Repo |
| `user_schema` | *обязательно* | Ваш модуль схемы User |
| `route_prefix` | `"/support"` | URL-префикс для всех маршрутов Escalated |
| `table_prefix` | `"escalated_"` | Префикс имён таблиц базы данных |
| `ui_enabled` | `true` | Подключить маршруты UI Inertia.js |
| `api_enabled` | `false` | Подключить маршруты JSON API |
| `admin_check` | `nil` | Функция `(user -> boolean)` для доступа администратора |
| `agent_check` | `nil` | Функция `(user -> boolean)` для доступа агента |
| `default_priority` | `:medium` | Приоритет тикета по умолчанию |
| `allow_customer_close` | `true` | Разрешить клиентам закрывать свои тикеты |
| `sla` | `%{enabled: true, ...}` | Карта конфигурации SLA |

## Настройка базы данных

Запустите миграцию Escalated:

```bash
mix ecto.gen.migration create_escalated_tables
```

Затем скопируйте содержимое миграции из `priv/repo/migrations/20260406000001_create_escalated_tables.exs` или установите через:

```bash
mix ecto.migrate
```

## Настройка маршрутизатора

Подключите маршруты Escalated в вашем маршрутизаторе Phoenix:

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

Это подключает:

- **Маршруты клиента** на `/support/tickets/*` — просмотр/создание/ответ на тикеты
- **Маршруты агента** на `/support/agent/*` — панель агента и управление тикетами
- **Маршруты администратора** на `/support/admin/*` — полное администрирование (отделы, теги, настройки)
- **Маршруты API** на `/support/api/v1/*` — JSON API (при `api_enabled: true`)

## Использование

### Программное создание тикетов

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Ответ на тикеты

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Назначение тикетов

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### Управление SLA

```elixir
# Проверка нарушений SLA (запускать периодически через планировщик)
breached = Escalated.Services.SlaService.check_breaches()

# Получение статистики SLA
stats = Escalated.Services.SlaService.stats()
```

## Отрисовка интерфейса

По умолчанию Escalated отрисовывает страницы через [Inertia.js](https://github.com/inertiajs/inertia-phoenix) при установленном `inertia_phoenix`. Если Inertia недоступен, контроллеры возвращают JSON-ответы.

Вы можете создавать собственные фронтенд-компоненты, потребляющие свойства страниц Inertia, или использовать JSON API напрямую.

## Плаги

Escalated предоставляет плаги для авторизации:

- `Escalated.Plugs.EnsureAgent` — требует, чтобы пользователь прошёл настроенную проверку `agent_check`
- `Escalated.Plugs.EnsureAdmin` — требует, чтобы пользователь прошёл настроенную проверку `admin_check`
- `Escalated.Plugs.ShareInertiaData` — передаёт общие данные Escalated на страницы Inertia

## Схемы

- `Escalated.Schemas.Ticket` — тикеты поддержки со статусом, приоритетом, отслеживанием SLA
- `Escalated.Schemas.Reply` — ответы на тикеты и внутренние заметки
- `Escalated.Schemas.Department` — отделы/команды поддержки
- `Escalated.Schemas.Tag` — теги тикетов для категоризации
- `Escalated.Schemas.SlaPolicy` — политики SLA с целями по приоритетам
- `Escalated.Schemas.TicketActivity` — журнал аудита изменений тикетов
- `Escalated.Schemas.AgentProfile` — данные профиля агента

## Лицензия

Лицензия MIT. Подробности в [LICENSE](LICENSE).
