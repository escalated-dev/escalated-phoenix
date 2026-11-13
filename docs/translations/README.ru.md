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
  <b>Русский</b> ·
  <a href="README.tr.md">Türkçe</a> ·
  <a href="README.zh-CN.md">简体中文</a>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Phoenix</h1>

<p align="center">
  Добавьте полноценный хелпдеск в ваше приложение на Phoenix.<br>
  Тикеты, SLA, правила эскалации, входящие для агентов и клиентский портал, на вашей собственной базе данных.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Документация</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Список изменений</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Входящие агента в Escalated: сохранённые представления со счётчиками, обратный отсчёт SLA и приоритет у каждого тикета" width="100%">
</picture>

## Что он делает

<table>
  <tr>
    <td width="40%">
      <h3>Входящие, в которых агентам удобно работать весь день</h3>
      Переписка, внутренние заметки, шаблоны ответов и таймеры SLA на одном экране. Тикеты также приходят по электронной почте через Postmark, Mailgun или SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Тикет, открытый в рабочем пространстве агента, с редактором ответа">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="Страница отчётов в админке со временем ответа, CSAT и нарушениями SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA и правила эскалации у вас на виду</h3>
      Цели по времени ответа и решения для каждого приоритета с учётом рабочих часов, правила, которые эскалируют или переназначают тикет при отставании, и отчёты о нарушениях.
    </td>
  </tr>
</table>

## Возможности

<table>
<tr>
<td width="33%" valign="top">

**Тикеты**
- Создание, назначение, ответ, решение, повторное открытие
- Настраиваемые переходы статусов
- Выделение ответа в новый тикет
- Откладывание с автоматическим возвратом
- Теги, вложения, история действий

</td>
<td width="33%" valign="top">

**Рабочее пространство агента**
- Очередь с фильтрами и сохранёнными представлениями
- Внутренние заметки и шаблоны ответов
- Отделы с автоматическим назначением
- Обновления в реальном времени через Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLA и маршрутизация**
- Цели по времени ответа и решения для каждого приоритета
- Рабочие часы
- Автоматическое обнаружение нарушений
- Видимость по отделам и аккаунтам, включается по желанию

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Клиенты**
- Портал самообслуживания: создание, ответ, отслеживание
- Проверенный гостевой доступ с истекающими правами
- Встраиваемый виджет с поиском по базе знаний
- База знаний, включается и отключается

</td>
<td width="33%" valign="top">

**Почта**
- Уведомления через ваш мейлер Swoosh
- Входящая почта через Postmark, Mailgun, SES
- Правильные цепочки писем в почтовых клиентах
- Шаблоны в вашем фирменном стиле

</td>
<td width="33%" valign="top">

**Администрирование и мультитенантность**
- Отделы, политики SLA, теги, отчёты
- Админка внутри вашей собственной панели администратора
- Мультитенантность по продавцам с местами для сотрудников
- Вложения в настраиваемом хранилище

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Все возможности подробно</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Быстрый старт

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Добавьте зависимость в `deps` в `mix.exs`, выполните миграции пакета, затем добавьте `use Escalated.Router` в ваш роутер. Требуются Elixir 1.15+ и Ecto SQL 3.14+. В [руководстве по началу работы](../getting-started.md) описаны пайплайны роутера.

## Подробнее

- [Все возможности](../features.md) · [Начало работы](../getting-started.md) · [Конфигурация, рендеринг интерфейса и plug](../configuration.md)
- [Темы тикетов, действия, использование и переводы](../customization.md) · [Уведомления и входящая почта](../email.md)
- [Управление доступом](../access-control.md) · [API-токены](../api-tokens.md) · [Доступ к тикетам и маршрутизация](../ticket-access-and-routing.md)
- [Доступ для продавцов и гостей](../merchant-and-guest-access.md) · [Встраивание виджета](../embedding-the-widget.md)
- [Панель агента](../agent-panel.md) · [Встраивание админки](../embedding-admin.md) · [Рассылки](../newsletters.md)

Escalated также доступен для [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) и [Filament](https://github.com/escalated-dev/escalated-filament). Интерфейс находится в [escalated](https://github.com/escalated-dev/escalated).

## Лицензия

MIT. Copyright (c) Escalated.dev. См. [LICENSE](../../LICENSE).
