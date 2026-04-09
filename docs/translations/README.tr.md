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
  <b>Türkçe</b> •
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated Phoenix için

Phoenix uygulamaları için gömülebilir yardım masası ve destek bilet sistemi. Hex paketi olarak hazır destek biletleri, departmanlar, SLA politikaları ve temsilci yönetimi.

## Özellikler

- **Bilet yaşam döngüsü** — Yapılandırılabilir durum geçişleriyle oluşturma, atama, yanıtlama, çözme, kapatma, yeniden açma
- **SLA motoru** — Önceliğe göre yanıt ve çözüm hedefleri, iş saatleri hesaplama, otomatik ihlal tespiti
- **Temsilci panosu** — Filtreler, dahili notlar, hazır yanıtlarla bilet kuyruğu
- **Müşteri portalı** — Self-servis bilet oluşturma, yanıtlar ve durum takibi
- **Yönetici paneli** — Departmanları, SLA politikalarını, etiketleri yönetin ve raporları görüntüleyin
- **Dosya ekleri** — Yapılandırılabilir depolama ve boyut limitleriyle sürükle-bırak yükleme
- **Etkinlik zaman çizelgesi** — Her biletteki her eylemin tam denetim günlüğü
- **Departman yönlendirme** — Otomatik atamayla temsilcileri departmanlara organize edin
- **Etiketleme sistemi** — Biletleri renkli etiketlerle kategorize edin
- **Bilet bölme** — Orijinal bağlamı koruyarak bir yanıtı yeni bağımsız bir bilete bölün
- **Bilet erteleme** — Ön ayarlarla biletleri erteleyin (1sa, 4sa, yarın, gelecek hafta); `mix escalated.wake_snoozed_tickets` Mix görevi onları programa göre otomatik olarak uyandırır
- **Kaydedilmiş görünümler / özel kuyruklar** — Filtre ön ayarlarını yeniden kullanılabilir bilet görünümleri olarak kaydedin, adlandırın ve paylaşın
- **Gömülebilir destek widget'ı** — KB araması, bilet formu ve durum kontrolü içeren hafif `<script>` widget'ı
- **E-posta dizileme** — Giden e-postalar, posta istemcilerinde doğru dizileme için uygun `In-Reply-To` ve `References` başlıklarını içerir
- **Markalı e-posta şablonları** — Tüm giden e-postalar için yapılandırılabilir logo, birincil renk ve altbilgi metni
- **Gerçek zamanlı yayın** — Otomatik yoklama yedeğiyle Phoenix PubSub aracılığıyla isteğe bağlı yayın
- **Bilgi bankası geçişi** — Yönetici ayarlarından genel bilgi bankasını etkinleştirin veya devre dışı bırakın

## Kurulum

`mix.exs` dosyasındaki bağımlılık listenize `escalated` ekleyin:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## Yapılandırma

`config/config.exs` dosyanıza şunu ekleyin:

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

### Yapılandırma Seçenekleri

| Seçenek | Varsayılan | Açıklama |
|--------|---------|-------------|
| `repo` | *gerekli* | Ecto Repo modülünüz |
| `user_schema` | *gerekli* | User şema modülünüz |
| `route_prefix` | `"/support"` | Tüm Escalated rotaları için URL öneki |
| `table_prefix` | `"escalated_"` | Veritabanı tablo adı öneki |
| `ui_enabled` | `true` | Inertia.js UI rotalarını bağla |
| `api_enabled` | `false` | JSON API rotalarını bağla |
| `admin_check` | `nil` | Yönetici erişimi için fonksiyon `(user -> boolean)` |
| `agent_check` | `nil` | Temsilci erişimi için fonksiyon `(user -> boolean)` |
| `default_priority` | `:medium` | Varsayılan bilet önceliği |
| `allow_customer_close` | `true` | Müşterilerin biletlerini kapatmasına izin ver |
| `sla` | `%{enabled: true, ...}` | SLA yapılandırma haritası |

## Veritabanı Kurulumu

Escalated migration'ını çalıştırın:

```bash
mix ecto.gen.migration create_escalated_tables
```

Ardından migration içeriğini `priv/repo/migrations/20260406000001_create_escalated_tables.exs` dosyasından kopyalayın veya şununla kurun:

```bash
mix ecto.migrate
```

## Yönlendirici Kurulumu

Phoenix yönlendiricinize Escalated rotalarını bağlayın:

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

Bu şunları bağlar:

- **Müşteri rotaları** `/support/tickets/*` adresinde — biletleri görüntüle/oluştur/yanıtla
- **Temsilci rotaları** `/support/agent/*` adresinde — temsilci panosu ve bilet yönetimi
- **Yönetici rotaları** `/support/admin/*` adresinde — tam yönetim (departmanlar, etiketler, ayarlar)
- **API rotaları** `/support/api/v1/*` adresinde — JSON API (`api_enabled: true` olduğunda)

## Kullanım

### Programatik olarak bilet oluşturma

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### Biletlere yanıt verme

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### Bilet atama

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### SLA Yönetimi

```elixir
# SLA ihlallerini kontrol et (bir zamanlayıcı aracılığıyla düzenli olarak çalıştırın)
breached = Escalated.Services.SlaService.check_breaches()

# SLA istatistiklerini al
stats = Escalated.Services.SlaService.stats()
```

## Arayüz Oluşturma

Varsayılan olarak, `inertia_phoenix` kurulu olduğunda Escalated sayfaları [Inertia.js](https://github.com/inertiajs/inertia-phoenix) aracılığıyla oluşturur. Inertia mevcut değilse, controller'lar JSON yanıtlarına geri döner.

Inertia sayfa prop'larını kullanan kendi frontend bileşenlerinizi oluşturabilir veya JSON API'yi doğrudan kullanabilirsiniz.

## Plug'lar

Escalated yetkilendirme için plug'lar sağlar:

- `Escalated.Plugs.EnsureAgent` — kullanıcının yapılandırılmış `agent_check` kontrolünü geçmesini gerektirir
- `Escalated.Plugs.EnsureAdmin` — kullanıcının yapılandırılmış `admin_check` kontrolünü geçmesini gerektirir
- `Escalated.Plugs.ShareInertiaData` — ortak Escalated verilerini Inertia sayfalarıyla paylaşır

## Şemalar

- `Escalated.Schemas.Ticket` — durum, öncelik, SLA takibini içeren destek biletleri
- `Escalated.Schemas.Reply` — bilet yanıtları ve dahili notlar
- `Escalated.Schemas.Department` — destek departmanları/takımları
- `Escalated.Schemas.Tag` — kategorize etmek için bilet etiketleri
- `Escalated.Schemas.SlaPolicy` — öncelik bazında hedeflerle SLA politikaları
- `Escalated.Schemas.TicketActivity` — bilet değişikliklerinin denetim günlüğü
- `Escalated.Schemas.AgentProfile` — temsilciye özel profil verileri

## Lisans

MIT Lisansı. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakın.
