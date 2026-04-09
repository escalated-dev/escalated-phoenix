<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <b>Español</b> •
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

# Escalated para Phoenix

Sistema de helpdesk y tickets de soporte integrable para aplicaciones Phoenix. Tickets de soporte, departamentos, políticas SLA y gestión de agentes listos para usar como paquete Hex.

## Características

- **Ciclo de vida del ticket** — Crear, asignar, responder, resolver, cerrar, reabrir con transiciones de estado configurables
- **Motor SLA** — Objetivos de respuesta y resolución por prioridad, cálculo de horas laborales, detección automática de infracciones
- **Panel del agente** — Cola de tickets con filtros, notas internas, respuestas predefinidas
- **Portal del cliente** — Creación de tickets autoservicio, respuestas y seguimiento de estado
- **Panel de administración** — Gestionar departamentos, políticas SLA, etiquetas y ver informes
- **Archivos adjuntos** — Carga por arrastrar y soltar con almacenamiento y límites de tamaño configurables
- **Línea de tiempo de actividad** — Registro de auditoría completo de cada acción en cada ticket
- **Enrutamiento por departamento** — Organizar agentes en departamentos con asignación automática
- **Sistema de etiquetas** — Categorizar tickets con etiquetas de colores
- **División de tickets** — Dividir una respuesta en un nuevo ticket independiente preservando el contexto original
- **Posponer tickets** — Posponer tickets con preajustes (1h, 4h, mañana, próxima semana); la tarea `mix escalated.wake_snoozed_tickets` los reactiva automáticamente según lo programado
- **Vistas guardadas / colas personalizadas** — Guardar, nombrar y compartir preajustes de filtros como vistas de tickets reutilizables
- **Widget de soporte integrable** — Widget `<script>` ligero con búsqueda en base de conocimiento, formulario de tickets y verificación de estado
- **Threading de correo electrónico** — Los correos salientes incluyen encabezados `In-Reply-To` y `References` correctos para el threading adecuado en clientes de correo
- **Plantillas de correo personalizadas** — Logo configurable, color primario y texto de pie de página para todos los correos salientes
- **Transmisión en tiempo real** — Transmisión opt-in a través de Phoenix PubSub con polling automático como respaldo
- **Alternador de base de conocimiento** — Habilitar o deshabilitar la base de conocimiento pública desde la configuración de administración

## Instalación

Agregue `escalated` a su lista de dependencias en `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Configuración

Agregue lo siguiente a su `config/config.exs`:

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

### Opciones de configuración

| Opción | Predeterminado | Descripción |
|--------|---------|-------------|
| `repo` | *requerido* | Su módulo Ecto Repo |
| `user_schema` | *requerido* | Su módulo de esquema de usuario |
| `route_prefix` | `"/support"` | Prefijo de URL para todas las rutas de Escalated |
| `table_prefix` | `"escalated_"` | Prefijo para nombres de tablas de base de datos |
| `ui_enabled` | `true` | Montar rutas de interfaz Inertia.js |
| `api_enabled` | `false` | Montar rutas de JSON API |
| `admin_check` | `nil` | Función `(user -> boolean)` para acceso de administrador |
| `agent_check` | `nil` | Función `(user -> boolean)` para acceso de agente |
| `default_priority` | `:medium` | Prioridad de ticket predeterminada |
| `allow_customer_close` | `true` | Permitir a los clientes cerrar sus tickets |
| `sla` | `%{enabled: true, ...}` | Mapa de configuración SLA |

## Configuración de base de datos

Ejecute la migración de Escalated:

```bash
mix ecto.gen.migration create_escalated_tables
```

Luego copie el contenido de la migración desde `priv/repo/migrations/20260406000001_create_escalated_tables.exs` o instale mediante:

```bash
mix ecto.migrate
```

## Configuración del enrutador

Monte las rutas de Escalated en su enrutador Phoenix:

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

Esto monta:

- **Rutas del cliente** en `/support/tickets/*` — ver/crear/responder tickets
- **Rutas del agente** en `/support/agent/*` — panel del agente y gestión de tickets
- **Rutas de administración** en `/support/admin/*` — administración completa (departamentos, etiquetas, configuración)
- **Rutas API** en `/support/api/v1/*` — JSON API (cuando `api_enabled: true`)

## Uso

### Crear tickets programáticamente

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Responder a tickets

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Asignar tickets

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### Gestión de SLA

```elixir
# Verificar infracciones de SLA (ejecutar periódicamente a través de un programador)
breached = Escalated.Services.SlaService.check_breaches()

# Obtener estadísticas de SLA
stats = Escalated.Services.SlaService.stats()
```

## Renderizado de UI

Por defecto, Escalated renderiza páginas a través de [Inertia.js](https://github.com/inertiajs/inertia-phoenix) cuando `inertia_phoenix` está instalado. Si Inertia no está disponible, los controladores recurren a respuestas JSON.

Puede construir sus propios componentes frontend que consuman las props de la página Inertia, o usar la JSON API directamente.

## Plugs

Escalated proporciona plugs para autorización:

- `Escalated.Plugs.EnsureAgent` — requiere que el usuario pase el `agent_check` configurado
- `Escalated.Plugs.EnsureAdmin` — requiere que el usuario pase el `admin_check` configurado
- `Escalated.Plugs.ShareInertiaData` — comparte datos comunes de Escalated con páginas Inertia

## Esquemas

- `Escalated.Schemas.Ticket` — tickets de soporte con estado, prioridad, seguimiento SLA
- `Escalated.Schemas.Reply` — respuestas de tickets y notas internas
- `Escalated.Schemas.Department` — departamentos/equipos de soporte
- `Escalated.Schemas.Tag` — etiquetas de tickets para categorización
- `Escalated.Schemas.SlaPolicy` — políticas SLA con objetivos por prioridad
- `Escalated.Schemas.TicketActivity` — registro de auditoría de cambios en tickets
- `Escalated.Schemas.AgentProfile` — datos de perfil específicos del agente

## Licencia

Licencia MIT. Consulte [LICENSE](LICENSE) para más detalles.
