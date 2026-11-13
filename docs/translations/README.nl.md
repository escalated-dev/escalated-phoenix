<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <b>Nederlands</b> ·
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
  Voeg een complete helpdesk toe aan je Phoenix-app.<br>
  Tickets, SLA's, escalatieregels, een inbox voor agents en een klantenportaal, draaiend op je eigen database.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentatie</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Wijzigingslog</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="De agent-inbox van Escalated: opgeslagen weergaven met aantallen, SLA-afteltimers en prioriteiten op elk ticket" width="100%">
</picture>

## Wat het doet

<table>
  <tr>
    <td width="40%">
      <h3>Een inbox waarin je agents de hele dag kunnen werken</h3>
      Gesprek, interne notities, standaardantwoorden en SLA-timers op één scherm. Tickets komen ook binnen per e-mail via Postmark, Mailgun of SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Een geopend ticket in de werkruimte van de agent met de antwoordeditor">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="De rapportagepagina voor beheerders met reactietijden, CSAT en SLA-overschrijdingen">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA's en escalatieregels die je kunt zien</h3>
      Reactie- en oplosdoelen per prioriteit met kantooruren, regels die escaleren of opnieuw toewijzen als een doel uitloopt, en rapporten over overschrijdingen.
    </td>
  </tr>
</table>

## Functies

<table>
<tr>
<td width="33%" valign="top">

**Tickets**
- Aanmaken, toewijzen, beantwoorden, oplossen, heropenen
- Instelbare statusovergangen
- Een antwoord afsplitsen naar een nieuw ticket
- Uitstellen met automatisch wekken
- Tags, bijlagen, activiteitentijdlijn

</td>
<td width="33%" valign="top">

**Werkruimte voor agents**
- Wachtrij met filters en opgeslagen weergaven
- Interne notities en standaardantwoorden
- Afdelingen met automatische toewijzing
- Realtime updates via Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLA's en routering**
- Reactie- en oplosdoelen per prioriteit
- Kantooruren
- Automatische detectie van overschrijdingen
- Optionele zichtbaarheid per afdeling en account

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Klanten**
- Selfserviceportaal: aanmaken, beantwoorden, volgen
- Geverifieerde gasttoegang met verlopende rechten
- Insluitbare widget met zoeken in de kennisbank
- Kennisbank, aan of uit

</td>
<td width="33%" valign="top">

**E-mail**
- Meldingen via je Swoosh-mailer
- Inkomend via Postmark, Mailgun, SES
- Correcte threads in mailprogramma's
- Templates in je eigen huisstijl

</td>
<td width="33%" valign="top">

**Beheer en multitenancy**
- Afdelingen, SLA-beleid, tags, rapporten
- Beheer binnen je eigen adminpaneel
- Multitenancy per merchant met plaatsen voor medewerkers
- Bijlagen op instelbare opslag

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Alle functies in detail</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Snel aan de slag

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Voeg de dependency toe aan `deps` in `mix.exs`, voer de migraties van het pakket uit en zet daarna `use Escalated.Router` in je router. Vereist Elixir 1.15+ en Ecto SQL 3.14+. De [handleiding om te beginnen](../getting-started.md) behandelt de router-pipelines.

## Meer informatie

- [Alle functies](../features.md) · [Aan de slag](../getting-started.md) · [Configuratie, UI-rendering en plugs](../configuration.md)
- [Ticketonderwerpen, acties, gebruik en vertalingen](../customization.md) · [Meldings- en inkomende e-mail](../email.md)
- [Toegangsbeheer](../access-control.md) · [API-tokens](../api-tokens.md) · [Tickettoegang en routering](../ticket-access-and-routing.md)
- [Toegang voor merchants en gasten](../merchant-and-guest-access.md) · [De widget insluiten](../embedding-the-widget.md)
- [Agentpaneel](../agent-panel.md) · [Het beheer insluiten](../embedding-admin.md) · [Nieuwsbrieven](../newsletters.md)

Escalated is ook beschikbaar voor [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) en [Filament](https://github.com/escalated-dev/escalated-filament). De UI staat in [escalated](https://github.com/escalated-dev/escalated).

## Licentie

MIT. Copyright (c) Escalated.dev. Zie [LICENSE](../../LICENSE).
