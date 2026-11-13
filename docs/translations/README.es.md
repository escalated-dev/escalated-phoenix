<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <b>Español</b> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <a href="README.pl.md">Polski</a> ·
  <a href="README.pt-BR.md">Português (BR)</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Phoenix</h1>

<p align="center">
  Añade un helpdesk completo a tu aplicación Phoenix.<br>
  Tickets, SLA, reglas de escalado, una bandeja de entrada para agentes y un portal de clientes, funcionando en tu propia base de datos.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentación</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Registro de cambios</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="La bandeja de entrada de agentes de Escalated: vistas guardadas con contadores, cuentas atrás de SLA y prioridades en cada ticket" width="100%">
</picture>

## Qué hace

<table>
  <tr>
    <td width="40%">
      <h3>Una bandeja de entrada en la que tus agentes pueden trabajar todo el día</h3>
      Conversación, notas internas, respuestas predefinidas y temporizadores de SLA en una sola pantalla. Los tickets también llegan por correo electrónico a través de Postmark, Mailgun o SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Un ticket abierto en el espacio de trabajo del agente con el editor de respuestas">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="La página de informes de administración con tiempos de respuesta, CSAT e incumplimientos de SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA y reglas de escalado que puedes ver</h3>
      Objetivos de respuesta y resolución por prioridad con horario laboral, reglas que escalan o reasignan cuando no se cumplen, e informes sobre incumplimientos.
    </td>
  </tr>
</table>

## Funciones

<table>
<tr>
<td width="33%" valign="top">

**Tickets**
- Crear, asignar, responder, resolver, reabrir
- Transiciones de estado configurables
- Dividir una respuesta en un ticket nuevo
- Posponer con reactivación automática
- Etiquetas, adjuntos, historial de actividad

</td>
<td width="33%" valign="top">

**Espacio de trabajo del agente**
- Cola con filtros y vistas guardadas
- Notas internas y respuestas predefinidas
- Departamentos con asignación automática
- Actualizaciones en tiempo real con Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLA y enrutamiento**
- Objetivos de respuesta y resolución por prioridad
- Horario laboral
- Detección automática de incumplimientos
- Visibilidad opcional por departamento y cuenta

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Clientes**
- Portal de autoservicio: abrir, responder, seguir
- Acceso de invitados verificado con permisos que caducan
- Widget integrable con búsqueda en la base de conocimiento
- Base de conocimiento, activada o desactivada

</td>
<td width="33%" valign="top">

**Correo**
- Notificaciones a través de tu mailer de Swoosh
- Correo entrante vía Postmark, Mailgun, SES
- Hilos correctos en los clientes de correo
- Plantillas con tu marca

</td>
<td width="33%" valign="top">

**Administración y multiinquilino**
- Departamentos, políticas de SLA, etiquetas, informes
- Administración dentro de tu propio panel
- Multiinquilino por comercio con plazas para el personal
- Adjuntos en almacenamiento configurable

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Todas las funciones en detalle</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Inicio rápido

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Añade la dependencia a `deps` en `mix.exs`, ejecuta las migraciones del paquete y luego pon `use Escalated.Router` en tu router. Requiere Elixir 1.15+ y Ecto SQL 3.14+. La [guía de primeros pasos](../getting-started.md) explica los pipelines del router.

## Más información

- [Todas las funciones](../features.md) · [Primeros pasos](../getting-started.md) · [Configuración, renderizado de la UI y plugs](../configuration.md)
- [Asuntos de tickets, acciones, uso y traducciones](../customization.md) · [Correo de notificaciones y entrante](../email.md)
- [Control de acceso](../access-control.md) · [Tokens de API](../api-tokens.md) · [Acceso a tickets y enrutamiento](../ticket-access-and-routing.md)
- [Acceso de comercios e invitados](../merchant-and-guest-access.md) · [Insertar el widget](../embedding-the-widget.md)
- [Panel del agente](../agent-panel.md) · [Insertar la administración](../embedding-admin.md) · [Boletines](../newsletters.md)

Escalated también está disponible para [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) y [Filament](https://github.com/escalated-dev/escalated-filament). La interfaz está en [escalated](https://github.com/escalated-dev/escalated).

## Licencia

MIT. Copyright (c) Escalated.dev. Consulta [LICENSE](../../LICENSE).
