<p align="center">
  <b>العربية</b> •
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
  <a href="README.zh-CN.md">简体中文</a>
</p>

# Escalated لـ Phoenix

نظام مكتب مساعدة وتذاكر دعم قابل للتضمين لتطبيقات Phoenix. تذاكر دعم وأقسام وسياسات SLA وإدارة وكلاء جاهزة للاستخدام كحزمة Hex.

## الميزات

- **دورة حياة التذكرة** — إنشاء، تعيين، رد، حل، إغلاق، إعادة فتح مع انتقالات حالة قابلة للتكوين
- **محرك SLA** — أهداف استجابة وحل لكل أولوية، حساب ساعات العمل، كشف تلقائي عن الانتهاكات
- **لوحة تحكم الوكيل** — قائمة انتظار التذاكر مع المرشحات والملاحظات الداخلية والردود الجاهزة
- **بوابة العميل** — إنشاء تذاكر ذاتية الخدمة والردود وتتبع الحالة
- **لوحة الإدارة** — إدارة الأقسام وسياسات SLA والعلامات وعرض التقارير
- **مرفقات الملفات** — تحميل بالسحب والإفلات مع تخزين وحدود حجم قابلة للتكوين
- **خط زمني النشاط** — سجل تدقيق كامل لكل إجراء على كل تذكرة
- **توجيه الأقسام** — تنظيم الوكلاء في أقسام مع التعيين التلقائي
- **نظام العلامات** — تصنيف التذاكر بعلامات ملونة
- **تقسيم التذاكر** — تقسيم رد إلى تذكرة مستقلة جديدة مع الحفاظ على السياق الأصلي
- **تأجيل التذاكر** — تأجيل التذاكر مع إعدادات مسبقة (ساعة، 4 ساعات، غداً، الأسبوع القادم)؛ مهمة `mix escalated.wake_snoozed_tickets` تُنبّهها تلقائياً حسب الجدول
- **العروض المحفوظة / قوائم الانتظار المخصصة** — حفظ وتسمية ومشاركة إعدادات المرشحات كعروض تذاكر قابلة لإعادة الاستخدام
- **أداة دعم قابلة للتضمين** — أداة `<script>` خفيفة مع بحث قاعدة المعرفة ونموذج التذاكر وفحص الحالة
- **تسلسل البريد الإلكتروني** — تتضمن رسائل البريد الصادرة رؤوس `In-Reply-To` و `References` الصحيحة للتسلسل الصحيح في عملاء البريد
- **قوالب بريد إلكتروني مخصصة** — شعار قابل للتكوين ولون أساسي ونص تذييل لجميع الرسائل الصادرة
- **البث في الوقت الفعلي** — بث اختياري عبر Phoenix PubSub مع استطلاع تلقائي احتياطي
- **تبديل قاعدة المعرفة** — تمكين أو تعطيل قاعدة المعرفة العامة من إعدادات الإدارة

## التثبيت

أضف `escalated` إلى قائمة التبعيات في `mix.exs`:

```elixir
def deps do
  [
    {:escalated_phoenix, "~> 0.1.0"}
  ]
end
```

## الإعدادات

أضف ما يلي إلى `config/config.exs`:

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

### خيارات الإعدادات

| الخيار | الافتراضي | الوصف |
|--------|---------|-------------|
| `repo` | *مطلوب* | وحدة Ecto Repo الخاصة بك |
| `user_schema` | *مطلوب* | وحدة مخطط المستخدم |
| `route_prefix` | `"/support"` | بادئة URL لجميع مسارات Escalated |
| `table_prefix` | `"escalated_"` | بادئة اسم جدول قاعدة البيانات |
| `ui_enabled` | `true` | تركيب مسارات واجهة Inertia.js |
| `api_enabled` | `false` | تركيب مسارات JSON API |
| `admin_check` | `nil` | دالة `(user -> boolean)` للوصول الإداري |
| `agent_check` | `nil` | دالة `(user -> boolean)` لوصول الوكيل |
| `default_priority` | `:medium` | أولوية التذكرة الافتراضية |
| `allow_customer_close` | `true` | السماح للعملاء بإغلاق تذاكرهم |
| `sla` | `%{enabled: true, ...}` | خريطة إعدادات SLA |

## إعداد قاعدة البيانات

قم بتشغيل هجرة Escalated:

```bash
mix ecto.gen.migration create_escalated_tables
```

ثم انسخ محتوى الهجرة من `priv/repo/migrations/20260406000001_create_escalated_tables.exs` أو ثبّت عبر:

```bash
mix ecto.migrate
```

## إعداد الموجه

قم بتركيب مسارات Escalated في موجه Phoenix:

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

يقوم هذا بتركيب:

- **مسارات العميل** في `/support/tickets/*` — عرض/إنشاء/الرد على التذاكر
- **مسارات الوكيل** في `/support/agent/*` — لوحة تحكم الوكيل وإدارة التذاكر
- **مسارات الإدارة** في `/support/admin/*` — إدارة كاملة (الأقسام، العلامات، الإعدادات)
- **مسارات API** في `/support/api/v1/*` — JSON API (عند تفعيل `api_enabled: true`)

## الاستخدام

### إنشاء التذاكر برمجياً

```elixir
{:ok, ticket} = Escalated.Services.TicketService.create(%{
  subject: "Cannot log in",
  description: "I'm getting a 500 error when trying to log in.",
  priority: "high",
  requester_id: user.id,
  requester_type: "MyApp.Accounts.User"
})
```

### الرد على التذاكر

```elixir
{:ok, reply} = Escalated.Services.TicketService.reply(ticket, %{
  body: "We're looking into this issue.",
  author_id: agent.id,
  is_internal: false
})
```

### تعيين التذاكر

```elixir
{:ok, ticket} = Escalated.Services.AssignmentService.assign(ticket, agent_id)
{:ok, ticket} = Escalated.Services.AssignmentService.auto_assign(ticket)
```

### إدارة SLA

```elixir
# التحقق من انتهاكات SLA (يتم تشغيلها دورياً عبر مُجدول)
breached = Escalated.Services.SlaService.check_breaches()

# الحصول على إحصائيات SLA
stats = Escalated.Services.SlaService.stats()
```

## عرض الواجهة

بشكل افتراضي، يعرض Escalated الصفحات عبر [Inertia.js](https://github.com/inertiajs/inertia-phoenix) عند تثبيت `inertia_phoenix`. إذا لم يكن Inertia متاحاً، تعود وحدات التحكم إلى استجابات JSON.

يمكنك بناء مكونات الواجهة الأمامية الخاصة بك التي تستهلك خصائص صفحة Inertia، أو استخدام JSON API مباشرة.

## المقابس

يوفر Escalated مقابس للتفويض:

- `Escalated.Plugs.EnsureAgent` — يتطلب من المستخدم اجتياز `agent_check` المُعدّ
- `Escalated.Plugs.EnsureAdmin` — يتطلب من المستخدم اجتياز `admin_check` المُعدّ
- `Escalated.Plugs.ShareInertiaData` — يشارك بيانات Escalated المشتركة مع صفحات Inertia

## المخططات

- `Escalated.Schemas.Ticket` — تذاكر الدعم مع الحالة والأولوية وتتبع SLA
- `Escalated.Schemas.Reply` — ردود التذاكر والملاحظات الداخلية
- `Escalated.Schemas.Department` — أقسام/فرق الدعم
- `Escalated.Schemas.Tag` — علامات التذاكر للتصنيف
- `Escalated.Schemas.SlaPolicy` — سياسات SLA مع أهداف لكل أولوية
- `Escalated.Schemas.TicketActivity` — سجل تدقيق تغييرات التذاكر
- `Escalated.Schemas.AgentProfile` — بيانات ملف تعريف الوكيل

## الرخصة

رخصة MIT. راجع [LICENSE](LICENSE) للتفاصيل.
