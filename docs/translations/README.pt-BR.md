<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.nl.md">Nederlands</a> ·
  <a href="README.pl.md">Polski</a> ·
  <b>Português (BR)</b> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Phoenix</h1>

<p align="center">
  Adicione um helpdesk completo ao seu app Phoenix.<br>
  Tickets, SLAs, regras de escalonamento, uma caixa de entrada para agentes e um portal do cliente, rodando no seu próprio banco de dados.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Documentação</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Histórico de mudanças</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="A caixa de entrada de agentes do Escalated: visualizações salvas com contagens, contagem regressiva de SLA e prioridades em cada ticket" width="100%">
</picture>

## O que ele faz

<table>
  <tr>
    <td width="40%">
      <h3>Uma caixa de entrada em que seus agentes conseguem trabalhar o dia todo</h3>
      Conversa, notas internas, respostas prontas e timers de SLA em uma única tela. Os tickets também chegam por e-mail via Postmark, Mailgun ou SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Um ticket aberto no espaço de trabalho do agente com o editor de resposta">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="A página de relatórios do admin com tempos de resposta, CSAT e violações de SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>SLAs e regras de escalonamento que você consegue ver</h3>
      Metas de resposta e resolução por prioridade com horário comercial, regras que escalonam ou reatribuem quando uma meta atrasa e relatórios de violações.
    </td>
  </tr>
</table>

## Recursos

<table>
<tr>
<td width="33%" valign="top">

**Tickets**
- Criar, atribuir, responder, resolver, reabrir
- Transições de status configuráveis
- Separar uma resposta em um novo ticket
- Adiar com reativação automática
- Tags, anexos, linha do tempo de atividades

</td>
<td width="33%" valign="top">

**Espaço de trabalho do agente**
- Fila com filtros e visualizações salvas
- Notas internas e respostas prontas
- Departamentos com atribuição automática
- Atualizações em tempo real via Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLAs e roteamento**
- Metas de resposta e resolução por prioridade
- Horário comercial
- Detecção automática de violações
- Visibilidade opcional por departamento e conta

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Clientes**
- Portal de autoatendimento: abrir, responder, acompanhar
- Acesso de convidados verificado com permissões que expiram
- Widget incorporável com busca na base de conhecimento
- Base de conhecimento, ligada ou desligada

</td>
<td width="33%" valign="top">

**E-mail**
- Notificações pelo seu mailer do Swoosh
- Entrada via Postmark, Mailgun, SES
- Threads corretas nos clientes de e-mail
- Templates com a sua marca

</td>
<td width="33%" valign="top">

**Admin e multitenancy**
- Departamentos, políticas de SLA, tags, relatórios
- Admin dentro do seu próprio painel administrativo
- Multitenancy por lojista com vagas para a equipe
- Anexos em armazenamento configurável

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Todos os recursos em detalhe</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Início rápido

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Adicione a dependência em `deps` no `mix.exs`, rode as migrations do pacote e depois coloque `use Escalated.Router` no seu router. Requer Elixir 1.15+ e Ecto SQL 3.14+. O [guia de primeiros passos](../getting-started.md) explica os pipelines do router.

## Saiba mais

- [Todos os recursos](../features.md) · [Primeiros passos](../getting-started.md) · [Configuração, renderização da UI e plugs](../configuration.md)
- [Assuntos de tickets, ações, uso e traduções](../customization.md) · [E-mail de notificação e de entrada](../email.md)
- [Controle de acesso](../access-control.md) · [Tokens de API](../api-tokens.md) · [Acesso a tickets e roteamento](../ticket-access-and-routing.md)
- [Acesso de lojistas e convidados](../merchant-and-guest-access.md) · [Incorporando o widget](../embedding-the-widget.md)
- [Painel do agente](../agent-panel.md) · [Incorporando o admin](../embedding-admin.md) · [Newsletters](../newsletters.md)

O Escalated também está disponível para [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) e [Filament](https://github.com/escalated-dev/escalated-filament). A interface fica em [escalated](https://github.com/escalated-dev/escalated).

## Licença

MIT. Copyright (c) Escalated.dev. Veja [LICENSE](../../LICENSE).
