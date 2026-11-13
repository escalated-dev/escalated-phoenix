<p align="center"><sub>
  <a href="README.ar.md">العربية</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="../../README.md">English</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <b>日本語</b> ·
  <a href="README.ko.md">한국어</a> ·
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
  Phoenix アプリに本格的なヘルプデスクを追加できます。<br>
  チケット、SLA、エスカレーションルール、エージェント用の受信トレイ、カスタマーポータルが、あなた自身のデータベース上で動きます。
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>ドキュメント</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>変更履歴</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="Escalated のエージェント受信トレイ: 件数付きの保存済みビュー、各チケットの SLA カウントダウンと優先度" width="100%">
</picture>

## できること

<table>
  <tr>
    <td width="40%">
      <h3>エージェントが一日中作業できる受信トレイ</h3>
      会話、内部メモ、定型返信、SLA タイマーを 1 つの画面にまとめています。チケットは Postmark、Mailgun、SES 経由のメールでも届きます。
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="エージェントのワークスペースで開いたチケットと返信エディター">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="応答時間、CSAT、SLA 違反を表示する管理者向けレポートページ">
      </picture>
    </td>
    <td width="40%">
      <h3>ひと目でわかる SLA とエスカレーションルール</h3>
      営業時間を考慮した優先度ごとの応答・解決目標、目標に遅れたときにエスカレーションや再割り当てを行うルール、違反に関するレポートを備えています。
    </td>
  </tr>
</table>

## 機能

<table>
<tr>
<td width="33%" valign="top">

**チケット**
- 作成、割り当て、返信、解決、再オープン
- 設定可能なステータス遷移
- 返信を新しいチケットに分割
- 自動で再開するスヌーズ
- タグ、添付ファイル、アクティビティ履歴

</td>
<td width="33%" valign="top">

**エージェントのワークスペース**
- フィルターと保存済みビュー付きのキュー
- 内部メモと定型返信
- 自動割り当て付きの部署
- Phoenix PubSub によるリアルタイム更新

</td>
<td width="33%" valign="top">

**SLA とルーティング**
- 優先度ごとの応答・解決目標
- 営業時間
- 違反の自動検出
- 部署とアカウント単位の表示制限 (オプトイン)

</td>
</tr>
<tr>
<td width="33%" valign="top">

**顧客**
- セルフサービスポータル: 起票、返信、進捗確認
- 期限付きの権限による認証済みゲストアクセス
- ナレッジベース検索付きの埋め込みウィジェット
- ナレッジベース (オン/オフ切り替え可)

</td>
<td width="33%" valign="top">

**メール**
- Swoosh メーラー経由の通知
- Postmark、Mailgun、SES 経由の受信
- メールクライアントでの正しいスレッド表示
- ブランドに合わせたテンプレート

</td>
<td width="33%" valign="top">

**管理とテナンシー**
- 部署、SLA ポリシー、タグ、レポート
- あなたの管理画面の中に組み込める管理機能
- スタッフ席付きのマーチャント単位のテナンシー
- 設定可能なストレージへの添付ファイル保存

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">すべての機能の詳細</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## クイックスタート

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

`mix.exs` の `deps` に依存関係を追加し、パッケージのマイグレーションを実行してから、ルーターに `use Escalated.Router` を書きます。Elixir 1.15 以上と Ecto SQL 3.14 以上が必要です。ルーターのパイプラインについては[スタートガイド](../getting-started.md)を参照してください。

## 詳しく知る

- [すべての機能](../features.md) · [はじめに](../getting-started.md) · [設定、UI のレンダリング、plug](../configuration.md)
- [チケットの件名、アクション、使い方、翻訳](../customization.md) · [通知メールと受信メール](../email.md)
- [アクセス制御](../access-control.md) · [API トークン](../api-tokens.md) · [チケットのアクセスとルーティング](../ticket-access-and-routing.md)
- [マーチャントとゲストのアクセス](../merchant-and-guest-access.md) · [ウィジェットの埋め込み](../embedding-the-widget.md)
- [エージェントパネル](../agent-panel.md) · [管理画面の埋め込み](../embedding-admin.md) · [ニュースレター](../newsletters.md)

Escalated は [Laravel](https://github.com/escalated-dev/escalated-laravel)、[Rails](https://github.com/escalated-dev/escalated-rails)、[Django](https://github.com/escalated-dev/escalated-django)、[NestJS](https://github.com/escalated-dev/escalated-nestjs)、[AdonisJS](https://github.com/escalated-dev/escalated-adonis)、[Symfony](https://github.com/escalated-dev/escalated-symfony)、[Go](https://github.com/escalated-dev/escalated-go)、[.NET](https://github.com/escalated-dev/escalated-dotnet)、[Spring](https://github.com/escalated-dev/escalated-spring)、[WordPress](https://github.com/escalated-dev/escalated-wordpress)、[Filament](https://github.com/escalated-dev/escalated-filament) 向けにも提供しています。UI は [escalated](https://github.com/escalated-dev/escalated) にあります。

## ライセンス

MIT。Copyright (c) Escalated.dev。詳細は [LICENSE](../../LICENSE) を参照してください。
