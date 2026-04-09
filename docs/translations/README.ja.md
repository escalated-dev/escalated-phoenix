<p align="center">
  <a href="README.ar.md">العربية</a> •
  <a href="README.de.md">Deutsch</a> •
  <a href="../../README.md">English</a> •
  <a href="README.es.md">Español</a> •
  <a href="README.fr.md">Français</a> •
  <a href="README.it.md">Italiano</a> •
  <b>日本語</b> •
  <a href="README.ko.md">한국어</a> •
  <a href="README.nl.md">Nederlands</a> •
  <a href="README.pl.md">Polski</a> •
  <a href="README.pt-BR.md">Português (BR)</a> •
  <a href="README.ru.md">Русский</a> •
  <a href="README.tr.md">Türkçe</a> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated for Phoenix

Phoenixアプリケーション向けの組み込み可能なヘルプデスクおよびサポートチケットシステム。Hexパッケージとして、サポートチケット、部門、SLAポリシー、エージェント管理をドロップインで提供します。

## 機能

- **チケットライフサイクル** — 設定可能なステータス遷移によるの作成、割り当て、返信、解決、クローズ、再開
- **SLAエンジン** — 優先度別の応答・解決目標、営業時間計算、自動違反検出
- **エージェントダッシュボード** — フィルター、内部メモ、定型応答付きのチケットキュー
- **カスタマーポータル** — セルフサービスのチケット作成、返信、ステータス追跡
- **管理パネル** — 部門、SLAポリシー、タグの管理とレポートの閲覧
- **ファイル添付** — 設定可能なストレージとサイズ制限付きのドラッグ＆ドロップアップロード
- **アクティビティタイムライン** — すべてのチケットのすべての操作の完全な監査ログ
- **部門ルーティング** — 自動割り当て付きでエージェントを部門に編成
- **タグシステム** — カラータグでチケットを分類
- **チケット分割** — 元のコンテキストを保持しながら返信を新しい独立したチケットに分割
- **チケットスヌーズ** — プリセット（1時間、4時間、明日、来週）でチケットをスヌーズ；`mix escalated.wake_snoozed_tickets` Mixタスクがスケジュールに従って自動的に起こします
- **保存済みビュー / カスタムキュー** — フィルタープリセットを再利用可能なチケットビューとして保存、命名、共有
- **埋め込み可能サポートウィジェット** — KB検索、チケットフォーム、ステータス確認付きの軽量 `<script>` ウィジェット
- **メールスレッディング** — 送信メールにメールクライアントでの正しいスレッド表示のための適切な `In-Reply-To` と `References` ヘッダーを含む
- **ブランド付きメールテンプレート** — すべての送信メールに設定可能なロゴ、プライマリカラー、フッターテキスト
- **リアルタイムブロードキャスト** — 自動ポーリングフォールバック付きのPhoenix PubSubによるオプトインブロードキャスト
- **ナレッジベーストグル** — 管理設定から公開ナレッジベースを有効/無効に切り替え

## インストール

`mix.exs` の依存関係リストに `escalated` を追加してください：

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## 設定

`config/config.exs` に以下を追加してください：

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

### 設定オプション

| オプション | デフォルト | 説明 |
|--------|---------|-------------|
| `repo` | *必須* | Ecto Repoモジュール |
| `user_schema` | *必須* | Userスキーマモジュール |
| `route_prefix` | `"/support"` | すべてのEscalatedルートのURLプレフィックス |
| `table_prefix` | `"escalated_"` | データベーステーブル名のプレフィックス |
| `ui_enabled` | `true` | Inertia.js UIルートをマウント |
| `api_enabled` | `false` | JSON APIルートをマウント |
| `admin_check` | `nil` | 管理者アクセス用の関数 `(user -> boolean)` |
| `agent_check` | `nil` | エージェントアクセス用の関数 `(user -> boolean)` |
| `default_priority` | `:medium` | デフォルトのチケット優先度 |
| `allow_customer_close` | `true` | 顧客が自分のチケットをクローズすることを許可 |
| `sla` | `%{enabled: true, ...}` | SLA設定マップ |

## データベースのセットアップ

Escalatedマイグレーションを実行してください：

```bash
mix ecto.gen.migration create_escalated_tables
```

次に `priv/repo/migrations/20260406000001_create_escalated_tables.exs` からマイグレーション内容をコピーするか、以下で実行してください：

```bash
mix ecto.migrate
```

## ルーターの設定

PhoenixルーターにEscalatedルートをマウントしてください：

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

これにより以下がマウントされます：

- **カスタマールート** `/support/tickets/*` — チケットの表示/作成/返信
- **エージェントルート** `/support/agent/*` — エージェントダッシュボードとチケット管理
- **管理ルート** `/support/admin/*` — 完全な管理（部門、タグ、設定）
- **APIルート** `/support/api/v1/*` — JSON API（`api_enabled: true` の場合）

## 使い方

### プログラムでチケットを作成

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### チケットに返信

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### チケットの割り当て

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA管理

```elixir
# SLA違反をチェック（スケジューラーで定期的に実行）
breached = Escalated.Services.SlaService.check_breaches()

# SLA統計を取得
stats = Escalated.Services.SlaService.stats()
```

## UIレンダリング

デフォルトでは、`inertia_phoenix` がインストールされている場合、Escalatedは [Inertia.js](https://github.com/inertiajs/inertia-phoenix) を通じてページをレンダリングします。Inertiaが利用できない場合、コントローラーはJSON応答にフォールバックします。

Inertiaページのpropsを消費する独自のフロントエンドコンポーネントを構築するか、JSON APIを直接使用できます。

## プラグ

Escalatedは認可用のプラグを提供します：

- `Escalated.Plugs.EnsureAgent` — 設定された `agent_check` にユーザーが合格することを要求
- `Escalated.Plugs.EnsureAdmin` — 設定された `admin_check` にユーザーが合格することを要求
- `Escalated.Plugs.ShareInertiaData` — 共通のEscalatedデータをInertiaページと共有

## スキーマ

- `Escalated.Schemas.Ticket` — ステータス、優先度、SLA追跡付きのサポートチケット
- `Escalated.Schemas.Reply` — チケットの返信と内部メモ
- `Escalated.Schemas.Department` — サポート部門/チーム
- `Escalated.Schemas.Tag` — 分類用のチケットタグ
- `Escalated.Schemas.SlaPolicy` — 優先度別目標付きのSLAポリシー
- `Escalated.Schemas.TicketActivity` — チケット変更の監査ログ
- `Escalated.Schemas.AgentProfile` — エージェント固有のプロファイルデータ

## ライセンス

MITライセンス。詳細は [LICENSE](LICENSE) を参照してください。
