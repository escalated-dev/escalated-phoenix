<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <b>Français</b> •
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

# Escalated pour Phoenix

Système d'assistance et de tickets de support intégrable pour les applications Phoenix. Tickets de support, départements, politiques SLA et gestion des agents prêts à l'emploi sous forme de package Hex.

## Fonctionnalités

- **Cycle de vie du ticket** — Créer, assigner, répondre, résoudre, fermer, rouvrir avec des transitions de statut configurables
- **Moteur SLA** — Objectifs de réponse et de résolution par priorité, calcul des heures ouvrables, détection automatique des violations
- **Tableau de bord agent** — File d'attente des tickets avec filtres, notes internes, réponses prédéfinies
- **Portail client** — Création de tickets en libre-service, réponses et suivi de statut
- **Panneau d'administration** — Gérer les départements, politiques SLA, tags et consulter les rapports
- **Pièces jointes** — Téléchargement par glisser-déposer avec stockage et limites de taille configurables
- **Chronologie des activités** — Journal d'audit complet de chaque action sur chaque ticket
- **Routage par département** — Organiser les agents en départements avec assignation automatique
- **Système de tags** — Catégoriser les tickets avec des tags colorés
- **Division de tickets** — Diviser une réponse en un nouveau ticket autonome tout en préservant le contexte d'origine
- **Mise en veille de tickets** — Mettre en veille les tickets avec des préréglages (1h, 4h, demain, semaine prochaine) ; la tâche `mix escalated.wake_snoozed_tickets` les réveille automatiquement selon le calendrier
- **Vues enregistrées / files personnalisées** — Enregistrer, nommer et partager des préréglages de filtres comme vues de tickets réutilisables
- **Widget de support intégrable** — Widget `<script>` léger avec recherche dans la base de connaissances, formulaire de ticket et vérification de statut
- **Threading d'e-mails** — Les e-mails sortants incluent les en-têtes `In-Reply-To` et `References` corrects pour un threading approprié dans les clients de messagerie
- **Modèles d'e-mails personnalisés** — Logo configurable, couleur primaire et texte de pied de page pour tous les e-mails sortants
- **Diffusion en temps réel** — Diffusion opt-in via Phoenix PubSub avec polling automatique en secours
- **Bascule de base de connaissances** — Activer ou désactiver la base de connaissances publique depuis les paramètres d'administration

## Installation

Ajoutez `escalated` à votre liste de dépendances dans `mix.exs` :

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Configuration

Ajoutez ce qui suit à votre `config/config.exs` :

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

### Options de configuration

| Option | Par défaut | Description |
|--------|---------|-------------|
| `repo` | *requis* | Votre module Ecto Repo |
| `user_schema` | *requis* | Votre module de schéma utilisateur |
| `route_prefix` | `"/support"` | Préfixe d'URL pour toutes les routes Escalated |
| `table_prefix` | `"escalated_"` | Préfixe des noms de tables de base de données |
| `ui_enabled` | `true` | Monter les routes UI Inertia.js |
| `api_enabled` | `false` | Monter les routes JSON API |
| `admin_check` | `nil` | Fonction `(user -> boolean)` pour l'accès admin |
| `agent_check` | `nil` | Fonction `(user -> boolean)` pour l'accès agent |
| `default_priority` | `:medium` | Priorité de ticket par défaut |
| `allow_customer_close` | `true` | Permettre aux clients de fermer leurs tickets |
| `sla` | `%{enabled: true, ...}` | Map de configuration SLA |

## Configuration de la base de données

Exécutez la migration Escalated :

```bash
mix ecto.gen.migration create_escalated_tables
```

Puis copiez le contenu de la migration depuis `priv/repo/migrations/20260406000001_create_escalated_tables.exs` ou installez via :

```bash
mix ecto.migrate
```

## Configuration du routeur

Montez les routes Escalated dans votre routeur Phoenix :

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

Ceci monte :

- **Routes client** sur `/support/tickets/*` — voir/créer/répondre aux tickets
- **Routes agent** sur `/support/agent/*` — tableau de bord agent et gestion des tickets
- **Routes admin** sur `/support/admin/*` — administration complète (départements, tags, paramètres)
- **Routes API** sur `/support/api/v1/*` — JSON API (quand `api_enabled: true`)

## Utilisation

### Créer des tickets par programmation

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Répondre aux tickets

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Assigner des tickets

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### Gestion SLA

```elixir
# Vérifier les violations SLA (exécuter périodiquement via un planificateur)
breached = Escalated.Services.SlaService.check_breaches()

# Obtenir les statistiques SLA
stats = Escalated.Services.SlaService.stats()
```

## Rendu de l'interface

Par défaut, Escalated rend les pages via [Inertia.js](https://github.com/inertiajs/inertia-phoenix) lorsque `inertia_phoenix` est installé. Si Inertia n'est pas disponible, les contrôleurs renvoient des réponses JSON.

Vous pouvez construire vos propres composants frontend qui consomment les props de page Inertia, ou utiliser directement l'API JSON.

## Plugs

Escalated fournit des plugs pour l'autorisation :

- `Escalated.Plugs.EnsureAgent` — exige que l'utilisateur passe le `agent_check` configuré
- `Escalated.Plugs.EnsureAdmin` — exige que l'utilisateur passe le `admin_check` configuré
- `Escalated.Plugs.ShareInertiaData` — partage les données communes Escalated avec les pages Inertia

## Schémas

- `Escalated.Schemas.Ticket` — tickets de support avec statut, priorité, suivi SLA
- `Escalated.Schemas.Reply` — réponses aux tickets et notes internes
- `Escalated.Schemas.Department` — départements/équipes de support
- `Escalated.Schemas.Tag` — tags de tickets pour la catégorisation
- `Escalated.Schemas.SlaPolicy` — politiques SLA avec objectifs par priorité
- `Escalated.Schemas.TicketActivity` — journal d'audit des modifications de tickets
- `Escalated.Schemas.AgentProfile` — données de profil spécifiques à l'agent

## Licence

Licence MIT. Voir [LICENSE](LICENSE) pour plus de détails.
