<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.ja.md">日本語</a> ·
  <b>한국어</b> ·
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
  Phoenix 앱에 완전한 헬프데스크를 추가하세요.<br>
  티켓, SLA, 에스컬레이션 규칙, 상담원 받은편지함, 고객 포털이 여러분의 데이터베이스에서 동작합니다.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>문서</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>변경 내역</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Escalated 상담원 받은편지함: 개수가 표시된 저장된 보기, 모든 티켓의 SLA 카운트다운과 우선순위" width="100%">
</picture>

## 주요 기능

<table>
  <tr>
    <td width="40%">
      <h3>상담원이 하루 종일 일할 수 있는 받은편지함</h3>
      대화, 내부 메모, 상용구 답변, SLA 타이머를 한 화면에서 볼 수 있습니다. 티켓은 Postmark, Mailgun 또는 SES를 통해 이메일로도 들어옵니다.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="답장 작성기가 표시된 상담원 작업 공간에서 열린 티켓">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="응답 시간, CSAT, SLA 위반을 보여주는 관리자 보고서 페이지">
      </picture>
    </td>
    <td width="40%">
      <h3>한눈에 보이는 SLA와 에스컬레이션 규칙</h3>
      영업시간을 반영한 우선순위별 응답 및 해결 목표, 목표가 지연되면 에스컬레이션하거나 재할당하는 규칙, 위반 보고서를 제공합니다.
    </td>
  </tr>
</table>

## 기능

<table>
<tr>
<td width="33%" valign="top">

**티켓**
- 생성, 할당, 답장, 해결, 다시 열기
- 설정 가능한 상태 전환
- 답장을 새 티켓으로 분리
- 자동으로 다시 깨어나는 스누즈
- 태그, 첨부 파일, 활동 타임라인

</td>
<td width="33%" valign="top">

**상담원 작업 공간**
- 필터와 저장된 보기가 있는 대기열
- 내부 메모와 상용구 답변
- 자동 할당이 되는 부서
- Phoenix PubSub를 통한 실시간 업데이트

</td>
<td width="33%" valign="top">

**SLA와 라우팅**
- 우선순위별 응답 및 해결 목표
- 영업시간
- 위반 자동 감지
- 선택적으로 켜는 부서 및 계정 단위 공개 범위

</td>
</tr>
<tr>
<td width="33%" valign="top">

**고객**
- 셀프 서비스 포털: 문의 등록, 답장, 진행 확인
- 만료되는 권한으로 검증된 게스트 접근
- 지식 베이스 검색이 있는 삽입형 위젯
- 켜고 끌 수 있는 지식 베이스

</td>
<td width="33%" valign="top">

**이메일**
- Swoosh 메일러를 통한 알림
- Postmark, Mailgun, SES를 통한 수신
- 메일 클라이언트에서 올바른 스레드 표시
- 브랜드에 맞춘 템플릿

</td>
<td width="33%" valign="top">

**관리와 테넌시**
- 부서, SLA 정책, 태그, 보고서
- 기존 관리자 패널 안에 들어가는 관리 화면
- 직원 좌석이 있는 판매자 단위 테넌시
- 설정 가능한 스토리지에 첨부 파일 저장

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">모든 기능 자세히 보기</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## 빠른 시작

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

`mix.exs`의 `deps`에 의존성을 추가하고, 패키지 마이그레이션을 실행한 다음, 라우터에 `use Escalated.Router`를 추가하세요. Elixir 1.15 이상과 Ecto SQL 3.14 이상이 필요합니다. 라우터 파이프라인은 [시작 가이드](../getting-started.md)에서 다룹니다.

## 더 알아보기

- [전체 기능](../features.md) · [시작하기](../getting-started.md) · [설정, UI 렌더링, plug](../configuration.md)
- [티켓 제목, 액션, 사용법, 번역](../customization.md) · [알림 이메일과 수신 이메일](../email.md)
- [접근 제어](../access-control.md) · [API 토큰](../api-tokens.md) · [티켓 접근과 라우팅](../ticket-access-and-routing.md)
- [판매자 및 게스트 접근](../merchant-and-guest-access.md) · [위젯 삽입](../embedding-the-widget.md)
- [상담원 패널](../agent-panel.md) · [관리 화면 삽입](../embedding-admin.md) · [뉴스레터](../newsletters.md)

Escalated는 [Laravel](https://github.com/escalated-dev/escalated-laravel), [Rails](https://github.com/escalated-dev/escalated-rails), [Django](https://github.com/escalated-dev/escalated-django), [NestJS](https://github.com/escalated-dev/escalated-nestjs), [AdonisJS](https://github.com/escalated-dev/escalated-adonis), [Symfony](https://github.com/escalated-dev/escalated-symfony), [Go](https://github.com/escalated-dev/escalated-go), [.NET](https://github.com/escalated-dev/escalated-dotnet), [Spring](https://github.com/escalated-dev/escalated-spring), [WordPress](https://github.com/escalated-dev/escalated-wordpress), [Filament](https://github.com/escalated-dev/escalated-filament)용으로도 제공됩니다. UI는 [escalated](https://github.com/escalated-dev/escalated) 저장소에 있습니다.

## 라이선스

MIT. Copyright (c) Escalated.dev. [LICENSE](../../LICENSE)를 참고하세요.
