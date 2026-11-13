<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <b>Italiano</b> ·
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
  Aggiungi un helpdesk completo alla tua app Phoenix.<br>
  Ticket, SLA, regole di escalation, una inbox per gli agenti e un portale clienti, sul tuo database.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentazione</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Registro delle modifiche</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="La inbox degli agenti di Escalated: viste salvate con conteggi, conti alla rovescia SLA e priorità su ogni ticket" width="100%">
</picture>

## Cosa fa

<table>
  <tr>
    <td width="40%">
      <h3>Una inbox in cui i tuoi agenti possono lavorare tutto il giorno</h3>
      Conversazione, note interne, risposte predefinite e timer SLA in un'unica schermata. I ticket arrivano anche via email tramite Postmark, Mailgun o SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Un ticket aperto nell'area di lavoro dell'agente con l'editor di risposta">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="La pagina dei report di amministrazione con tempi di risposta, CSAT e violazioni degli SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA e regole di escalation sempre visibili</h3>
      Obiettivi di risposta e risoluzione per priorità con orari lavorativi, regole che eseguono l'escalation o riassegnano quando un obiettivo slitta, e report sulle violazioni.
    </td>
  </tr>
</table>

## Funzionalità

<table>
<tr>
<td width="33%" valign="top">

**Ticket**
- Crea, assegna, rispondi, risolvi, riapri
- Transizioni di stato configurabili
- Dividi una risposta in un nuovo ticket
- Posticipa con riattivazione automatica
- Tag, allegati, cronologia delle attività

</td>
<td width="33%" valign="top">

**Area di lavoro dell'agente**
- Coda con filtri e viste salvate
- Note interne e risposte predefinite
- Reparti con assegnazione automatica
- Aggiornamenti in tempo reale tramite Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLA e instradamento**
- Obiettivi di risposta e risoluzione per priorità
- Orari lavorativi
- Rilevamento automatico delle violazioni
- Visibilità per reparto e account, se la attivi

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Clienti**
- Portale self-service: apri, rispondi, segui
- Accesso ospite verificato con permessi a scadenza
- Widget incorporabile con ricerca nella knowledge base
- Knowledge base, attiva o disattiva

</td>
<td width="33%" valign="top">

**Email**
- Notifiche tramite il tuo mailer Swoosh
- Email in entrata via Postmark, Mailgun, SES
- Thread corretti nei client di posta
- Template con il tuo brand

</td>
<td width="33%" valign="top">

**Amministrazione e multi-tenancy**
- Reparti, policy SLA, tag, report
- Amministrazione dentro il tuo pannello di admin
- Multi-tenancy per merchant con posti per lo staff
- Allegati su storage configurabile

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Tutte le funzionalità nel dettaglio</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Avvio rapido

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Aggiungi la dipendenza a `deps` in `mix.exs`, esegui le migrazioni del pacchetto, poi metti `use Escalated.Router` nel tuo router. Richiede Elixir 1.15+ e Ecto SQL 3.14+. La [guida introduttiva](../getting-started.md) spiega le pipeline del router.

## Per saperne di più

- [Tutte le funzionalità](../features.md) · [Per iniziare](../getting-started.md) · [Configurazione, rendering della UI e plug](../configuration.md)
- [Oggetti dei ticket, azioni, utilizzo e traduzioni](../customization.md) · [Email di notifica e in entrata](../email.md)
- [Controllo degli accessi](../access-control.md) · [Token API](../api-tokens.md) · [Accesso ai ticket e instradamento](../ticket-access-and-routing.md)
- [Accesso merchant e ospite](../merchant-and-guest-access.md) · [Incorporare il widget](../embedding-the-widget.md)
- [Pannello agente](../agent-panel.md) · [Incorporare l'amministrazione](../embedding-admin.md) · [Newsletter](../newsletters.md)

Escalated è disponibile anche per [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) e [Filament](https://github.com/escalated-dev/escalated-filament). L'interfaccia si trova in [escalated](https://github.com/escalated-dev/escalated).

## Licenza

MIT. Copyright (c) Escalated.dev. Vedi [LICENSE](../../LICENSE).
