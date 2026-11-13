<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <b>Français</b> ·
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
  Ajoutez un helpdesk complet à votre application Phoenix.<br>
  Tickets, SLA, règles d'escalade, une boîte de réception pour les agents et un portail client, sur votre propre base de données.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentation</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Journal des modifications</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="La boîte de réception des agents d'Escalated : vues enregistrées avec compteurs, comptes à rebours SLA et priorités sur chaque ticket" width="100%">
</picture>

## Ce qu'il fait

<table>
  <tr>
    <td width="40%">
      <h3>Une boîte de réception où vos agents peuvent travailler toute la journée</h3>
      Conversation, notes internes, réponses prédéfinies et minuteurs SLA sur un seul écran. Les tickets arrivent aussi par e-mail via Postmark, Mailgun ou SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Un ticket ouvert dans l'espace de travail de l'agent avec l'éditeur de réponse">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="La page de rapports de l'administration avec les temps de réponse, le CSAT et les dépassements de SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>Des SLA et des règles d'escalade bien visibles</h3>
      Des objectifs de réponse et de résolution par priorité avec heures ouvrées, des règles qui escaladent ou réattribuent quand un objectif glisse, et des rapports sur les dépassements.
    </td>
  </tr>
</table>

## Fonctionnalités

<table>
<tr>
<td width="33%" valign="top">

**Tickets**
- Créer, attribuer, répondre, résoudre, rouvrir
- Transitions de statut configurables
- Scinder une réponse en nouveau ticket
- Mise en attente avec réveil automatique
- Tags, pièces jointes, historique d'activité

</td>
<td width="33%" valign="top">

**Espace de travail des agents**
- File d'attente avec filtres et vues enregistrées
- Notes internes et réponses prédéfinies
- Départements avec attribution automatique
- Mises à jour en temps réel via Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLA et routage**
- Objectifs de réponse et de résolution par priorité
- Heures ouvrées
- Détection automatique des dépassements
- Visibilité par département et par compte, en option

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Clients**
- Portail en libre-service : ouvrir, répondre, suivre
- Accès invité vérifié avec autorisations qui expirent
- Widget intégrable avec recherche dans la base de connaissances
- Base de connaissances, activée ou non

</td>
<td width="33%" valign="top">

**E-mail**
- Notifications via votre mailer Swoosh
- E-mails entrants via Postmark, Mailgun, SES
- Fils de discussion corrects dans les clients mail
- Modèles à vos couleurs

</td>
<td width="33%" valign="top">

**Administration et multi-tenant**
- Départements, politiques SLA, tags, rapports
- Administration intégrée à votre propre panneau d'admin
- Multi-tenant par marchand avec sièges pour le personnel
- Pièces jointes sur un stockage configurable

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Toutes les fonctionnalités en détail</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Démarrage rapide

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Ajoutez la dépendance à `deps` dans `mix.exs`, lancez les migrations du paquet, puis ajoutez `use Escalated.Router` dans votre routeur. Nécessite Elixir 1.15+ et Ecto SQL 3.14+. Le [guide de démarrage](../getting-started.md) explique les pipelines du routeur.

## En savoir plus

- [Toutes les fonctionnalités](../features.md) · [Premiers pas](../getting-started.md) · [Configuration, rendu de l'interface et plugs](../configuration.md)
- [Sujets des tickets, actions, utilisation et traductions](../customization.md) · [E-mails de notification et entrants](../email.md)
- [Contrôle d'accès](../access-control.md) · [Tokens d'API](../api-tokens.md) · [Accès aux tickets et routage](../ticket-access-and-routing.md)
- [Accès marchand et invité](../merchant-and-guest-access.md) · [Intégrer le widget](../embedding-the-widget.md)
- [Panneau agent](../agent-panel.md) · [Intégrer l'administration](../embedding-admin.md) · [Newsletters](../newsletters.md)

Escalated est aussi disponible pour [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) et [Filament](https://github.com/escalated-dev/escalated-filament). L'interface se trouve dans [escalated](https://github.com/escalated-dev/escalated).

## Licence

MIT. Copyright (c) Escalated.dev. Voir [LICENSE](../../LICENSE).
