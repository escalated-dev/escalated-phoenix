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
  <b>Polski</b> ·
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
  Dodaj kompletny helpdesk do swojej aplikacji Phoenix.<br>
  Zgłoszenia, SLA, reguły eskalacji, skrzynka dla agentów i portal klienta, działające na Twojej własnej bazie danych.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>Dokumentacja</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>Lista zmian</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Skrzynka agenta w Escalated: zapisane widoki z licznikami, odliczanie SLA i priorytety przy każdym zgłoszeniu" width="100%">
</picture>

## Co robi

<table>
  <tr>
    <td width="40%">
      <h3>Skrzynka, w której Twoi agenci mogą pracować cały dzień</h3>
      Rozmowa, notatki wewnętrzne, gotowe odpowiedzi i liczniki SLA na jednym ekranie. Zgłoszenia przychodzą też e-mailem przez Postmark, Mailgun lub SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="Zgłoszenie otwarte w obszarze roboczym agenta z edytorem odpowiedzi">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="Strona raportów w panelu administracyjnym z czasami odpowiedzi, CSAT i naruszeniami SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>SLA i reguły eskalacji, które widać</h3>
      Cele czasu odpowiedzi i rozwiązania dla każdego priorytetu z uwzględnieniem godzin pracy, reguły, które eskalują lub ponownie przypisują zgłoszenie, gdy termin się przesuwa, oraz raporty naruszeń.
    </td>
  </tr>
</table>

## Funkcje

<table>
<tr>
<td width="33%" valign="top">

**Zgłoszenia**
- Tworzenie, przypisywanie, odpowiadanie, rozwiązywanie, ponowne otwieranie
- Konfigurowalne przejścia statusów
- Wydzielenie odpowiedzi do nowego zgłoszenia
- Odkładanie z automatycznym wybudzeniem
- Tagi, załączniki, oś czasu aktywności

</td>
<td width="33%" valign="top">

**Obszar roboczy agenta**
- Kolejka z filtrami i zapisanymi widokami
- Notatki wewnętrzne i gotowe odpowiedzi
- Działy z automatycznym przypisywaniem
- Aktualizacje w czasie rzeczywistym przez Phoenix PubSub

</td>
<td width="33%" valign="top">

**SLA i routing**
- Cele czasu odpowiedzi i rozwiązania dla każdego priorytetu
- Godziny pracy
- Automatyczne wykrywanie naruszeń
- Opcjonalna widoczność według działu i konta

</td>
</tr>
<tr>
<td width="33%" valign="top">

**Klienci**
- Portal samoobsługowy: zgłaszanie, odpowiadanie, śledzenie
- Zweryfikowany dostęp dla gości z wygasającymi uprawnieniami
- Osadzany widżet z wyszukiwaniem w bazie wiedzy
- Baza wiedzy, włączona lub wyłączona

</td>
<td width="33%" valign="top">

**E-mail**
- Powiadomienia przez Twój mailer Swoosh
- Poczta przychodząca przez Postmark, Mailgun, SES
- Poprawne wątki w programach pocztowych
- Szablony z Twoją marką

</td>
<td width="33%" valign="top">

**Administracja i wielodostępność**
- Działy, polityki SLA, tagi, raporty
- Administracja wewnątrz Twojego panelu admina
- Wielodostępność dla sprzedawców z miejscami dla personelu
- Załączniki w konfigurowalnym magazynie

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">Wszystkie funkcje szczegółowo</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## Szybki start

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

Dodaj zależność do `deps` w `mix.exs`, uruchom migracje pakietu, a potem dodaj `use Escalated.Router` do swojego routera. Wymaga Elixir 1.15+ i Ecto SQL 3.14+. [Przewodnik na start](../getting-started.md) opisuje pipeline'y routera.

## Dowiedz się więcej

- [Wszystkie funkcje](../features.md) · [Pierwsze kroki](../getting-started.md) · [Konfiguracja, renderowanie UI i plugi](../configuration.md)
- [Tematy zgłoszeń, akcje, użycie i tłumaczenia](../customization.md) · [Powiadomienia e-mail i poczta przychodząca](../email.md)
- [Kontrola dostępu](../access-control.md) · [Tokeny API](../api-tokens.md) · [Dostęp do zgłoszeń i routing](../ticket-access-and-routing.md)
- [Dostęp dla sprzedawców i gości](../merchant-and-guest-access.md) · [Osadzanie widżetu](../embedding-the-widget.md)
- [Panel agenta](../agent-panel.md) · [Osadzanie panelu administracyjnego](../embedding-admin.md) · [Newslettery](../newsletters.md)

Escalated jest dostępny również dla [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress) i [Filament](https://github.com/escalated-dev/escalated-filament). Interfejs znajduje się w [escalated](https://github.com/escalated-dev/escalated).

## Licencja

MIT. Copyright (c) Escalated.dev. Zobacz [LICENSE](../../LICENSE).
