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
  <a href="README.pt-BR.md">Português (BR)</a> ·
  <a href="README.ru.md">Русский</a> ·
  <a href="README.tr.md">Türkçe</a> ·
  <b>简体中文</b>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Phoenix</h1>

<p align="center">
  为你的 Phoenix 应用添加一套完整的帮助台。<br>
  工单、SLA、升级规则、客服收件箱和客户门户，全部运行在你自己的数据库上。
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>文档</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>更新日志</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Escalated 客服收件箱：带计数的已保存视图，每个工单上都有 SLA 倒计时和优先级" width="100%">
</picture>

## 它能做什么

<table>
  <tr>
    <td width="40%">
      <h3>客服可以整天使用的收件箱</h3>
      对话、内部备注、预设回复和 SLA 计时器都在同一个界面上。工单也可以通过 Postmark、Mailgun 或 SES 以邮件形式进入。
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="在客服工作区中打开的工单和回复编辑器">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="管理后台的报表页面，显示响应时间、CSAT 和 SLA 违约情况">
      </picture>
    </td>
    <td width="40%">
      <h3>清晰可见的 SLA 和升级规则</h3>
      按优先级设定响应和解决目标并支持工作时间，目标延误时自动升级或重新分配，还提供违约报表。
    </td>
  </tr>
</table>

## 功能

<table>
<tr>
<td width="33%" valign="top">

**工单**
- 创建、分配、回复、解决、重新打开
- 可配置的状态流转
- 将回复拆分为新工单
- 暂缓并自动唤醒
- 标签、附件、活动时间线

</td>
<td width="33%" valign="top">

**客服工作区**
- 带筛选和已保存视图的队列
- 内部备注和预设回复
- 带自动分配的部门
- 通过 Phoenix PubSub 实时更新

</td>
<td width="33%" valign="top">

**SLA 与路由**
- 按优先级设定响应和解决目标
- 工作时间
- 自动检测违约
- 可选的按部门和账户的可见性

</td>
</tr>
<tr>
<td width="33%" valign="top">

**客户**
- 自助服务门户：提交、回复、跟踪
- 带有效期授权的已验证访客访问
- 可嵌入的小部件，支持知识库搜索
- 知识库，可开可关

</td>
<td width="33%" valign="top">

**邮件**
- 通过你的 Swoosh 邮件发送器发送通知
- 通过 Postmark、Mailgun、SES 接收邮件
- 邮件客户端中正确的会话串
- 带品牌的模板

</td>
<td width="33%" valign="top">

**管理与多租户**
- 部门、SLA 策略、标签、报表
- 管理界面嵌入你自己的管理后台
- 按商户划分的多租户，含员工席位
- 附件存储位置可配置

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">查看全部功能详情</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## 快速开始

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

在 `mix.exs` 的 `deps` 中添加依赖，运行包自带的迁移，然后在你的路由器中加入 `use Escalated.Router`。需要 Elixir 1.15+ 和 Ecto SQL 3.14+。[入门指南](../getting-started.md)介绍了路由器的 pipeline 配置。

## 了解更多

- [全部功能](../features.md) · [入门](../getting-started.md) · [配置、界面渲染和 plug](../configuration.md)
- [工单主题、操作、用量和翻译](../customization.md) · [通知邮件和入站邮件](../email.md)
- [访问控制](../access-control.md) · [API 令牌](../api-tokens.md) · [工单访问与路由](../ticket-access-and-routing.md)
- [商户和访客访问](../merchant-and-guest-access.md) · [嵌入小部件](../embedding-the-widget.md)
- [客服面板](../agent-panel.md) · [嵌入管理界面](../embedding-admin.md) · [邮件通讯](../newsletters.md)

Escalated 也提供 [Laravel](https://github.com/escalated-dev/escalated-laravel)、[Rails](https://github.com/escalated-dev/escalated-rails)、[Django](https://github.com/escalated-dev/escalated-django)、[NestJS](https://github.com/escalated-dev/escalated-nestjs)、[AdonisJS](https://github.com/escalated-dev/escalated-adonis)、[Symfony](https://github.com/escalated-dev/escalated-symfony)、[Go](https://github.com/escalated-dev/escalated-go)、[.NET](https://github.com/escalated-dev/escalated-dotnet)、[Spring](https://github.com/escalated-dev/escalated-spring)、[WordPress](https://github.com/escalated-dev/escalated-wordpress) 和 [Filament](https://github.com/escalated-dev/escalated-filament) 版本。界面代码位于 [escalated](https://github.com/escalated-dev/escalated)。

## 许可证

MIT。Copyright (c) Escalated.dev。详见 [LICENSE](../../LICENSE)。
