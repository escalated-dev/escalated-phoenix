<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <b>Deutsch</b> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
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
  Füge deiner Phoenix-App einen vollständigen Helpdesk hinzu.<br>
  Tickets, SLAs, Eskalationsregeln, ein Agenten-Posteingang und ein Kundenportal, direkt auf deiner eigenen Datenbank.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Dokumentation</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Änderungsprotokoll</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Der Agenten-Posteingang von Escalated: gespeicherte Ansichten mit Zählern, SLA-Countdowns und Prioritäten an jedem Ticket" width="100%">
</picture>

## Was es kann

<table>
  <tr>
    <td width="40%">
      <h3>Ein Posteingang, in dem deine Agenten den ganzen Tag arbeiten können</h3>
      Konversation, interne Notizen, Textbausteine und SLA-Timer auf einem Bildschirm. Tickets kommen auch per E-Mail über Postmark, Mailgun oder SES an.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Ein geöffnetes Ticket im Agenten-Arbeitsbereich mit dem Antwort-Editor">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="Die Berichtsseite im Adminbereich mit Antwortzeiten, CSAT und SLA-Verstößen">
      </picture>
    </td>
    <td width="40%">
      <h3>SLAs und Eskalationsregeln, die du im Blick hast</h3>
      Reaktions- und Lösungsziele pro Priorität mit Geschäftszeiten, Regeln, die eskalieren oder neu zuweisen, wenn ein Ziel verfehlt wird, und Berichte über Verstöße.
    </td>
  </tr>
</table>

## Funktionen

<table>
<tr>
<td width="33%" valign="top">

**Tickets**
- Erstellen, zuweisen, antworten, lösen, wieder öffnen
- Konfigurierbare Statusübergänge
- Eine Antwort in ein neues Ticket aufteilen
- Zurückstellen mit automatischer Wiedervorlage
- Tags, Anhänge, Aktivitätsverlauf

</td>
<td width="33%" valign="top">

**Agenten-Arbeitsbereich**
- Warteschlange mit Filtern und gespeicherten Ansichten
- Interne Notizen und Textbausteine
- Abteilungen mit automatischer Zuweisung
- Echtzeit-Updates über Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLAs und Routing**
- Reaktions- und Lösungsziele pro Priorität
- Geschäftszeiten
- Automatische Erkennung von Verstößen
- Optionale Sichtbarkeit nach Abteilung und Konto

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Kunden**
- Self-Service-Portal: eröffnen, antworten, verfolgen
- Verifizierter Gastzugang mit ablaufenden Freigaben
- Einbettbares Widget mit Wissensdatenbank-Suche
- Wissensdatenbank, ein- oder ausschaltbar

</td>
<td width="33%" valign="top">

**E-Mail**
- Benachrichtigungen über deinen Swoosh-Mailer
- Eingehend über Postmark, Mailgun, SES
- Korrekte Thread-Darstellung in Mail-Clients
- Vorlagen in deinem Branding

</td>
<td width="33%" valign="top">

**Verwaltung und Mandanten**
- Abteilungen, SLA-Richtlinien, Tags, Berichte
- Adminbereich in deinem eigenen Admin-Panel
- Händler-Mandanten mit Plätzen für Mitarbeiter
- Anhänge auf konfigurierbarem Speicher

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Alle Funktionen im Detail</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Schnellstart

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Füge die Abhängigkeit zu `deps` in `mix.exs` hinzu, führe die Migrationen des Pakets aus und setze dann `use Escalated.Router` in deinen Router. Voraussetzungen: Elixir 1.15+ und Ecto SQL 3.14+. Die [Einstiegsanleitung](../getting-started.md) erklärt die Router-Pipelines.

## Mehr erfahren

- [Alle Funktionen](../features.md) · [Erste Schritte](../getting-started.md) · [Konfiguration, UI-Rendering und Plugs](../configuration.md)
- [Ticket-Betreffe, Aktionen, Nutzung und Übersetzungen](../customization.md) · [Benachrichtigungen und eingehende E-Mails](../email.md)
- [Zugriffskontrolle](../access-control.md) · [API-Tokens](../api-tokens.md) · [Ticketzugriff und Routing](../ticket-access-and-routing.md)
- [Händler- und Gastzugang](../merchant-and-guest-access.md) · [Widget einbetten](../embedding-the-widget.md)
- [Agenten-Panel](../agent-panel.md) · [Adminbereich einbetten](../embedding-admin.md) · [Newsletter](../newsletters.md)

Escalated gibt es auch für [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) und [Filament](https://github.com/escalated-dev/escalated-filament). Die Oberfläche liegt in [escalated](https://github.com/escalated-dev/escalated).

## Lizenz

MIT. Copyright (c) Escalated.dev. Siehe [LICENSE](../../LICENSE).
