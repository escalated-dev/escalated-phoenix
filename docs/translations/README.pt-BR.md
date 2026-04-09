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
  <b>Português (BR)</b> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated para Phoenix

Sistema de helpdesk e tickets de suporte incorporável para aplicações Phoenix. Tickets de suporte, departamentos, políticas de SLA e gerenciamento de agentes prontos para uso como pacote Hex.

## Recursos

- **Ciclo de vida do ticket** — Criar, atribuir, responder, resolver, fechar, reabrir com transições de status configuráveis
- **Motor SLA** — Metas de resposta e resolução por prioridade, cálculo de horário comercial, detecção automática de violações
- **Painel do agente** — Fila de tickets com filtros, notas internas, respostas prontas
- **Portal do cliente** — Criação de tickets autoatendimento, respostas e acompanhamento de status
- **Painel administrativo** — Gerenciar departamentos, políticas de SLA, tags e visualizar relatórios
- **Anexos de arquivos** — Upload por arrastar e soltar com armazenamento e limites de tamanho configuráveis
- **Linha do tempo de atividades** — Log de auditoria completo de cada ação em cada ticket
- **Roteamento por departamento** — Organizar agentes em departamentos com atribuição automática
- **Sistema de tags** — Categorizar tickets com tags coloridas
- **Divisão de tickets** — Dividir uma resposta em um novo ticket independente preservando o contexto original
- **Soneca de tickets** — Adiar tickets com predefinições (1h, 4h, amanhã, próxima semana); a tarefa `mix escalated.wake_snoozed_tickets` os desperta automaticamente conforme programado
- **Visualizações salvas / filas personalizadas** — Salvar, nomear e compartilhar predefinições de filtros como visualizações de tickets reutilizáveis
- **Widget de suporte incorporável** — Widget `<script>` leve com busca na base de conhecimento, formulário de ticket e verificação de status
- **Threading de e-mail** — E-mails enviados incluem cabeçalhos `In-Reply-To` e `References` corretos para threading adequado em clientes de e-mail
- **Templates de e-mail personalizados** — Logo configurável, cor primária e texto de rodapé para todos os e-mails enviados
- **Transmissão em tempo real** — Transmissão opt-in via Phoenix PubSub com polling automático como fallback
- **Toggle da base de conhecimento** — Habilitar ou desabilitar a base de conhecimento pública nas configurações de administração

## Instalação

Adicione `escalated` à sua lista de dependências em `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Configuração

Adicione o seguinte ao seu `config/config.exs`:

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

### Opções de configuração

| Opção | Padrão | Descrição |
|--------|---------|-------------|
| `repo` | *obrigatório* | Seu módulo Ecto Repo |
| `user_schema` | *obrigatório* | Seu módulo de schema User |
| `route_prefix` | `"/support"` | Prefixo de URL para todas as rotas do Escalated |
| `table_prefix` | `"escalated_"` | Prefixo dos nomes das tabelas do banco de dados |
| `ui_enabled` | `true` | Montar rotas da UI Inertia.js |
| `api_enabled` | `false` | Montar rotas da JSON API |
| `admin_check` | `nil` | Função `(user -> boolean)` para acesso de administrador |
| `agent_check` | `nil` | Função `(user -> boolean)` para acesso de agente |
| `default_priority` | `:medium` | Prioridade padrão do ticket |
| `allow_customer_close` | `true` | Permitir que clientes fechem seus tickets |
| `sla` | `%{enabled: true, ...}` | Mapa de configuração SLA |

## Configuração do banco de dados

Execute a migration do Escalated:

```bash
mix ecto.gen.migration create_escalated_tables
```

Em seguida, copie o conteúdo da migration de `priv/repo/migrations/20260406000001_create_escalated_tables.exs` ou instale via:

```bash
mix ecto.migrate
```

## Configuração do roteador

Monte as rotas do Escalated no seu roteador Phoenix:

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

Isso monta:

- **Rotas do cliente** em `/support/tickets/*` — visualizar/criar/responder tickets
- **Rotas do agente** em `/support/agent/*` — painel do agente e gerenciamento de tickets
- **Rotas de admin** em `/support/admin/*` — administração completa (departamentos, tags, configurações)
- **Rotas da API** em `/support/api/v1/*` — JSON API (quando `api_enabled: true`)

## Uso

### Criando tickets programaticamente

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Respondendo tickets

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Atribuindo tickets

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### Gerenciamento de SLA

```elixir
# Verificar violações de SLA (executar periodicamente via agendador)
breached = Escalated.Services.SlaService.check_breaches()

# Obter estatísticas de SLA
stats = Escalated.Services.SlaService.stats()
```

## Renderização da UI

Por padrão, o Escalated renderiza páginas via [Inertia.js](https://github.com/inertiajs/inertia-phoenix) quando `inertia_phoenix` está instalado. Se o Inertia não estiver disponível, os controllers recorrem a respostas JSON.

Você pode construir seus próprios componentes frontend que consomem as props da página Inertia, ou usar a JSON API diretamente.

## Plugs

O Escalated fornece plugs para autorização:

- `Escalated.Plugs.EnsureAgent` — requer que o usuário passe o `agent_check` configurado
- `Escalated.Plugs.EnsureAdmin` — requer que o usuário passe o `admin_check` configurado
- `Escalated.Plugs.ShareInertiaData` — compartilha dados comuns do Escalated com páginas Inertia

## Schemas

- `Escalated.Schemas.Ticket` — tickets de suporte com status, prioridade, rastreamento de SLA
- `Escalated.Schemas.Reply` — respostas de tickets e notas internas
- `Escalated.Schemas.Department` — departamentos/equipes de suporte
- `Escalated.Schemas.Tag` — tags de tickets para categorização
- `Escalated.Schemas.SlaPolicy` — políticas de SLA com metas por prioridade
- `Escalated.Schemas.TicketActivity` — log de auditoria de alterações de tickets
- `Escalated.Schemas.AgentProfile` — dados de perfil específicos do agente

## Licença

Licença MIT. Veja [LICENSE](LICENSE) para detalhes.
