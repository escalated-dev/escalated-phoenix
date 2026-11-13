<p align="center"><sub>
  <b>العربية</b> ·
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
  <a href="README.zh-CN.md">简体中文</a>
</sub></p>

<p align="center">
  <a href="https://escalated.dev"><img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/logo.png" width="72" height="72" alt="Escalated"></a>
</p>

<h1 align="center">Escalated for Phoenix</h1>

<p align="center">
  أضف مكتب دعم متكاملًا إلى تطبيق Phoenix الخاص بك.<br>
  تذاكر، واتفاقيات مستوى الخدمة (SLA)، وقواعد تصعيد، وصندوق وارد للوكلاء، وبوابة للعملاء، تعمل كلها على قاعدة بياناتك الخاصة.
</p>

<p align="center">
  <a href="https://escalated.dev"><b>Website</b></a> ·
  <a href="https://escalated.dev/docs"><b>التوثيق</b></a> ·
  <a href="https://escalated.dev/cloud"><b>Cloud</b></a> ·
  <a href="../../CHANGELOG.md"><b>سجل التغييرات</b></a>
</p>

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-dark.png">
  <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/inbox-light.png" alt="صندوق الوارد للوكلاء في Escalated: عروض محفوظة مع أعدادها، وعدّاد تنازلي لـ SLA وأولوية على كل تذكرة" width="100%">
</picture>

## ما الذي يقدمه

<table>
  <tr>
    <td width="40%">
      <h3>صندوق وارد يمكن لوكلائك العمل فيه طوال اليوم</h3>
      المحادثة والملاحظات الداخلية والردود الجاهزة ومؤقتات SLA في شاشة واحدة. تصل التذاكر أيضًا عبر البريد الإلكتروني من خلال Postmark أو Mailgun أو SES.
    </td>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/ticket-light.png" alt="تذكرة مفتوحة في مساحة عمل الوكيل مع محرر الرد">
      </picture>
    </td>
  </tr>
  <tr>
    <td width="60%">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-dark.png">
        <img src="https://raw.githubusercontent.com/escalated-dev/escalated/main/docs/assets/readme/dashboard-light.png" alt="صفحة التقارير في لوحة الإدارة مع أوقات الاستجابة وCSAT وحالات خرق SLA">
      </picture>
    </td>
    <td width="40%">
      <h3>اتفاقيات SLA وقواعد تصعيد واضحة أمامك</h3>
      أهداف للاستجابة والحل حسب الأولوية مع مراعاة ساعات العمل، وقواعد تصعّد التذكرة أو تعيد إسنادها عند التأخر، وتقارير عن حالات الخرق.
    </td>
  </tr>
</table>

## الميزات

<table>
<tr>
<td width="33%" valign="top">

**التذاكر**
- الإنشاء والإسناد والرد والحل وإعادة الفتح
- انتقالات حالة قابلة للتهيئة
- تقسيم رد إلى تذكرة جديدة
- تأجيل مع إعادة تنبيه تلقائية
- الوسوم والمرفقات وسجل النشاط

</td>
<td width="33%" valign="top">

**مساحة عمل الوكيل**
- قائمة انتظار مع عوامل تصفية وعروض محفوظة
- ملاحظات داخلية وردود جاهزة
- أقسام مع إسناد تلقائي
- تحديثات فورية عبر Phoenix PubSub

</td>
<td width="33%" valign="top">

**اتفاقيات SLA والتوجيه**
- أهداف للاستجابة والحل حسب الأولوية
- ساعات العمل
- اكتشاف تلقائي لحالات الخرق
- رؤية اختيارية حسب القسم والحساب

</td>
</tr>
<tr>
<td width="33%" valign="top">

**العملاء**
- بوابة خدمة ذاتية: فتح التذاكر والرد والمتابعة
- وصول موثَّق للضيوف بصلاحيات تنتهي مدتها
- أداة قابلة للتضمين مع بحث في قاعدة المعرفة
- قاعدة معرفة يمكنك تفعيلها أو إيقافها

</td>
<td width="33%" valign="top">

**البريد الإلكتروني**
- إشعارات عبر مُرسِل Swoosh الخاص بك
- بريد وارد عبر Postmark وMailgun وSES
- تسلسل صحيح للمحادثات في برامج البريد
- قوالب تحمل علامتك التجارية

</td>
<td width="33%" valign="top">

**الإدارة وتعدد المستأجرين**
- الأقسام وسياسات SLA والوسوم والتقارير
- الإدارة داخل لوحة الإدارة الخاصة بك
- تعدد مستأجرين للتجار مع مقاعد للموظفين
- مرفقات على تخزين قابل للتهيئة

</td>
</tr>
</table>

<p align="center"><sub><a href="../features.md">كل الميزات بالتفصيل</a></sub></p>

<p align="center">
  <a href="https://www.phoenixframework.org"><img src="https://img.shields.io/badge/Phoenix-FD4F00?style=for-the-badge&logo=phoenixframework&logoColor=white" alt="Phoenix"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir_1.15+-4B275F?style=for-the-badge&logo=elixir&logoColor=white" alt="Elixir 1.15+"></a>
  <a href="https://inertiajs.com"><img src="https://img.shields.io/badge/Inertia-9553E9?style=for-the-badge&logo=inertia&logoColor=white" alt="Inertia"></a>
  <a href="https://vuejs.org"><img src="https://img.shields.io/badge/Vue_3-4FC08D?style=for-the-badge&logo=vuedotjs&logoColor=white" alt="Vue 3"></a>
</p>

## البدء السريع

```elixir
{:escalated, "~> 0.2.14", hex: :escalated_phoenix}
```

```bash
mix ecto.migrate -r MyApp.SupportRepo --migrations-path deps/escalated/priv/repo/migrations
```

أضف الاعتمادية إلى `deps` في `mix.exs`، وشغّل ترحيلات الحزمة، ثم أضف `use Escalated.Router` إلى الموجّه (router). يتطلب Elixir 1.15+ وEcto SQL 3.14+. يشرح [دليل البدء](../getting-started.md) مسارات الموجّه (pipelines).

## اعرف المزيد

- [كل الميزات](../features.md) · [البدء](../getting-started.md) · [الإعدادات وعرض الواجهة والـ plugs](../configuration.md)
- [عناوين التذاكر والإجراءات والاستخدام والترجمات](../customization.md) · [البريد الإلكتروني للإشعارات والوارد](../email.md)
- [التحكم في الوصول](../access-control.md) · [رموز API](../api-tokens.md) · [الوصول إلى التذاكر وتوجيهها](../ticket-access-and-routing.md)
- [وصول التجار والضيوف](../merchant-and-guest-access.md) · [تضمين الأداة](../embedding-the-widget.md)
- [لوحة الوكيل](../agent-panel.md) · [تضمين لوحة الإدارة](../embedding-admin.md) · [النشرات البريدية](../newsletters.md)

يتوفر Escalated أيضًا لـ [Laravel](https://github.com/escalated-dev/escalated-laravel)، [Rails](https://github.com/escalated-dev/escalated-rails)، [Django](https://github.com/escalated-dev/escalated-django)، [NestJS](https://github.com/escalated-dev/escalated-nestjs)، [AdonisJS](https://github.com/escalated-dev/escalated-adonis)، [Symfony](https://github.com/escalated-dev/escalated-symfony)، [Go](https://github.com/escalated-dev/escalated-go)، [.NET](https://github.com/escalated-dev/escalated-dotnet)، [Spring](https://github.com/escalated-dev/escalated-spring)، [WordPress](https://github.com/escalated-dev/escalated-wordpress) و[Filament](https://github.com/escalated-dev/escalated-filament). توجد الواجهة في [escalated](https://github.com/escalated-dev/escalated).

## الترخيص

MIT. Copyright (c) Escalated.dev. راجع [LICENSE](../../LICENSE).
