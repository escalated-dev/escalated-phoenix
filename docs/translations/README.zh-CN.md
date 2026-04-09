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
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <b>简体中文</b>
</p>

# Escalated Phoenix 版

Phoenix 应用程序的可嵌入帮助台和支持工单系统。作为 Hex 包提供即插即用的支持工单、部门、SLA 策略和客服管理。

## 功能特性

- **工单生命周期** — 创建、分配、回复、解决、关闭、重新打开，具有可配置的状态转换
- **SLA 引擎** — 按优先级的响应和解决目标、工作时间计算、自动违规检测
- **客服仪表板** — 带筛选器、内部备注、预设回复的工单队列
- **客户门户** — 自助工单创建、回复和状态跟踪
- **管理面板** — 管理部门、SLA 策略、标签并查看报告
- **文件附件** — 可配置存储和大小限制的拖放上传
- **活动时间线** — 每张工单每个操作的完整审计日志
- **部门路由** — 将客服组织到部门中并自动分配
- **标签系统** — 使用彩色标签对工单进行分类
- **工单拆分** — 将回复拆分为新的独立工单，同时保留原始上下文
- **工单暂停** — 使用预设（1小时、4小时、明天、下周）暂停工单；`mix escalated.wake_snoozed_tickets` Mix 任务按计划自动唤醒
- **保存的视图 / 自定义队列** — 将筛选预设保存、命名和共享为可重用的工单视图
- **可嵌入支持小部件** — 带知识库搜索、工单表单和状态检查的轻量级 `<script>` 小部件
- **邮件线程** — 发出的邮件包含正确的 `In-Reply-To` 和 `References` 头部，以便在邮件客户端中正确分组
- **品牌邮件模板** — 所有发出邮件的可配置 Logo、主色调和页脚文字
- **实时广播** — 通过 Phoenix PubSub 进行可选广播，带自动轮询回退
- **知识库开关** — 从管理设置中启用或禁用公共知识库

## 安装

在 `mix.exs` 的依赖列表中添加 `escalated`：

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## 配置

在 `config/config.exs` 中添加以下内容：

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

### 配置选项

| 选项 | 默认值 | 描述 |
|--------|---------|-------------|
| `repo` | *必需* | 你的 Ecto Repo 模块 |
| `user_schema` | *必需* | 你的 User schema 模块 |
| `route_prefix` | `"/support"` | 所有 Escalated 路由的 URL 前缀 |
| `table_prefix` | `"escalated_"` | 数据库表名前缀 |
| `ui_enabled` | `true` | 挂载 Inertia.js UI 路由 |
| `api_enabled` | `false` | 挂载 JSON API 路由 |
| `admin_check` | `nil` | 管理员访问函数 `(user -> boolean)` |
| `agent_check` | `nil` | 客服访问函数 `(user -> boolean)` |
| `default_priority` | `:medium` | 默认工单优先级 |
| `allow_customer_close` | `true` | 允许客户关闭自己的工单 |
| `sla` | `%{enabled: true, ...}` | SLA 配置映射 |

## 数据库设置

运行 Escalated 迁移：

```bash
mix ecto.gen.migration create_escalated_tables
```

然后从 `priv/repo/migrations/20260406000001_create_escalated_tables.exs` 复制迁移内容，或通过以下命令安装：

```bash
mix ecto.migrate
```

## 路由器设置

在 Phoenix 路由器中挂载 Escalated 路由：

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

这将挂载：

- **客户路由** 在 `/support/tickets/*` — 查看/创建/回复工单
- **客服路由** 在 `/support/agent/*` — 客服仪表板和工单管理
- **管理路由** 在 `/support/admin/*` — 完整管理（部门、标签、设置）
- **API 路由** 在 `/support/api/v1/*` — JSON API（当 `api_enabled: true` 时）

## 使用方法

### 通过代码创建工单

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### 回复工单

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### 分配工单

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA 管理

```elixir
# 检查 SLA 违规（通过调度器定期运行）
breached = Escalated.Services.SlaService.check_breaches()

# 获取 SLA 统计
stats = Escalated.Services.SlaService.stats()
```

## UI 渲染

默认情况下，当安装了 `inertia_phoenix` 时，Escalated 通过 [Inertia.js](https://github.com/inertiajs/inertia-phoenix) 渲染页面。如果 Inertia 不可用，控制器将回退到 JSON 响应。

您可以构建自己的前端组件来消费 Inertia 页面 props，或直接使用 JSON API。

## Plugs

Escalated 提供用于授权的 plugs：

- `Escalated.Plugs.EnsureAgent` — 要求用户通过配置的 `agent_check`
- `Escalated.Plugs.EnsureAdmin` — 要求用户通过配置的 `admin_check`
- `Escalated.Plugs.ShareInertiaData` — 与 Inertia 页面共享通用 Escalated 数据

## 模式

- `Escalated.Schemas.Ticket` — 带状态、优先级、SLA 跟踪的支持工单
- `Escalated.Schemas.Reply` — 工单回复和内部备注
- `Escalated.Schemas.Department` — 支持部门/团队
- `Escalated.Schemas.Tag` — 用于分类的工单标签
- `Escalated.Schemas.SlaPolicy` — 带按优先级目标的 SLA 策略
- `Escalated.Schemas.TicketActivity` — 工单变更审计日志
- `Escalated.Schemas.AgentProfile` — 客服特定的档案数据

## 许可证

MIT 许可证。详情请参阅 [LICENSE](LICENSE)。
