<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <a href="README.ja.md">日本語</a> •
  <b>한국어</b> •
  <a href="README.nl.md">Nederlands</a> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated for Phoenix

Phoenix 애플리케이션을 위한 임베디드 헬프데스크 및 지원 티켓 시스템. Hex 패키지로 지원 티켓, 부서, SLA 정책 및 에이전트 관리를 즉시 사용할 수 있습니다.

## 기능

- **티켓 라이프사이클** — 구성 가능한 상태 전환으로 생성, 할당, 답변, 해결, 닫기, 재오픈
- **SLA 엔진** — 우선순위별 응답 및 해결 목표, 업무 시간 계산, 자동 위반 감지
- **에이전트 대시보드** — 필터, 내부 메모, 정형 응답이 포함된 티켓 큐
- **고객 포털** — 셀프서비스 티켓 생성, 답변 및 상태 추적
- **관리자 패널** — 부서, SLA 정책, 태그 관리 및 보고서 조회
- **파일 첨부** — 구성 가능한 저장소 및 크기 제한이 있는 드래그 앤 드롭 업로드
- **활동 타임라인** — 모든 티켓의 모든 작업에 대한 전체 감사 로그
- **부서 라우팅** — 자동 할당으로 에이전트를 부서로 구성
- **태그 시스템** — 색상 태그로 티켓 분류
- **티켓 분할** — 원본 컨텍스트를 보존하면서 답변을 새로운 독립 티켓으로 분할
- **티켓 스누즈** — 프리셋(1시간, 4시간, 내일, 다음 주)으로 티켓 스누즈; `mix escalated.wake_snoozed_tickets` Mix 태스크가 일정에 따라 자동으로 깨움
- **저장된 뷰 / 커스텀 큐** — 필터 프리셋을 재사용 가능한 티켓 뷰로 저장, 이름 지정, 공유
- **임베디드 지원 위젯** — KB 검색, 티켓 폼, 상태 확인이 포함된 경량 `<script>` 위젯
- **이메일 스레딩** — 발신 이메일에 메일 클라이언트에서의 올바른 스레딩을 위한 적절한 `In-Reply-To` 및 `References` 헤더 포함
- **브랜드 이메일 템플릿** — 모든 발신 이메일에 구성 가능한 로고, 기본 색상, 푸터 텍스트
- **실시간 브로드캐스팅** — 자동 폴링 폴백이 있는 Phoenix PubSub을 통한 옵트인 브로드캐스팅
- **지식 베이스 토글** — 관리자 설정에서 공개 지식 베이스 활성화 또는 비활성화

## 설치

`mix.exs`의 의존성 목록에 `escalated`를 추가하세요:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## 설정

`config/config.exs`에 다음을 추가하세요:

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

### 구성 옵션

| 옵션 | 기본값 | 설명 |
|--------|---------|-------------|
| `repo` | *필수* | Ecto Repo 모듈 |
| `user_schema` | *필수* | User 스키마 모듈 |
| `route_prefix` | `"/support"` | 모든 Escalated 라우트의 URL 접두사 |
| `table_prefix` | `"escalated_"` | 데이터베이스 테이블명 접두사 |
| `ui_enabled` | `true` | Inertia.js UI 라우트 마운트 |
| `api_enabled` | `false` | JSON API 라우트 마운트 |
| `admin_check` | `nil` | 관리자 접근용 함수 `(user -> boolean)` |
| `agent_check` | `nil` | 에이전트 접근용 함수 `(user -> boolean)` |
| `default_priority` | `:medium` | 기본 티켓 우선순위 |
| `allow_customer_close` | `true` | 고객이 자신의 티켓을 닫을 수 있도록 허용 |
| `sla` | `%{enabled: true, ...}` | SLA 설정 맵 |

## 데이터베이스 설정

Escalated 마이그레이션을 실행하세요:

```bash
mix ecto.gen.migration create_escalated_tables
```

그런 다음 `priv/repo/migrations/20260406000001_create_escalated_tables.exs`에서 마이그레이션 내용을 복사하거나 다음을 통해 설치하세요:

```bash
mix ecto.migrate
```

## 라우터 설정

Phoenix 라우터에 Escalated 라우트를 마운트하세요:

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

이것은 다음을 마운트합니다:

- **고객 라우트** `/support/tickets/*` — 티켓 보기/생성/답변
- **에이전트 라우트** `/support/agent/*` — 에이전트 대시보드 및 티켓 관리
- **관리자 라우트** `/support/admin/*` — 전체 관리 (부서, 태그, 설정)
- **API 라우트** `/support/api/v1/*` — JSON API (`api_enabled: true` 시)

## 사용법

### 프로그래밍 방식으로 티켓 생성

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### 티켓에 답변

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### 티켓 할당

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA 관리

```elixir
# SLA 위반 확인 (스케줄러를 통해 주기적으로 실행)
breached = Escalated.Services.SlaService.check_breaches()

# SLA 통계 가져오기
stats = Escalated.Services.SlaService.stats()
```

## UI 렌더링

기본적으로 Escalated는 `inertia_phoenix`가 설치되어 있을 때 [Inertia.js](https://github.com/inertiajs/inertia-phoenix)를 통해 페이지를 렌더링합니다. Inertia를 사용할 수 없는 경우 컨트롤러는 JSON 응답으로 폴백합니다.

Inertia 페이지 props를 소비하는 자체 프론트엔드 컴포넌트를 구축하거나 JSON API를 직접 사용할 수 있습니다.

## 플러그

Escalated는 인가를 위한 플러그를 제공합니다:

- `Escalated.Plugs.EnsureAgent` — 사용자가 구성된 `agent_check`를 통과할 것을 요구
- `Escalated.Plugs.EnsureAdmin` — 사용자가 구성된 `admin_check`를 통과할 것을 요구
- `Escalated.Plugs.ShareInertiaData` — 공통 Escalated 데이터를 Inertia 페이지와 공유

## 스키마

- `Escalated.Schemas.Ticket` — 상태, 우선순위, SLA 추적이 포함된 지원 티켓
- `Escalated.Schemas.Reply` — 티켓 답변 및 내부 메모
- `Escalated.Schemas.Department` — 지원 부서/팀
- `Escalated.Schemas.Tag` — 분류용 티켓 태그
- `Escalated.Schemas.SlaPolicy` — 우선순위별 목표가 포함된 SLA 정책
- `Escalated.Schemas.TicketActivity` — 티켓 변경 감사 로그
- `Escalated.Schemas.AgentProfile` — 에이전트 관련 프로필 데이터

## 라이선스

MIT 라이선스. 자세한 내용은 [LICENSE](LICENSE)를 참조하세요.
