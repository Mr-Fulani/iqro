# KFGQPC official production source package request

Дата подготовки: 25 августа 2026 года.

## Кому отправить

- To: `developer@qurancomplex.gov.sa`
- CC: `info@qurancomplex.gov.sa`
- Отправитель: рабочий адрес проекта `iqro.forum@gmail.com`

Это контакты, опубликованные King Fahd Glorious Qur'an Printing Complex на developer platform
и в официальном Quran Hafs guide. Секреты, API credentials и внутренние серверные URL в письмо
не добавлять.

## Что именно запрашивается

Нужен не произвольный PDF из стороннего зеркала, а официальный immutable source package:

1. полный Madinah Mushaf, Hafs ʿan ʿAsim, 604-page vector artwork или другой официальный
   page-image master, разрешённый для приложений;
2. официальный Uthmanic Hafs text/data package в JSON/CSV/SQL/XML и соответствующие fonts;
3. page, surah, ayah, juz, hizb и line mapping, если он входит в официальный пакет;
4. точное имя и номер версии, дата выпуска, исходный filename, размер и опубликованные
   checksums;
5. user manual, terms/license и требуемый attribution;
6. письменное подтверждение допустимости неизменяющего технического преобразования page artwork
   в WebP, размещения immutable assets в Cloudflare R2/CDN и отображения в first-party Web,
   iOS/Android и Telegram Mini App.

## Готовое письмо

**Subject:** Request for official Madinah Mushaf Hafs production source package and usage confirmation — Iqro

Hello King Fahd Glorious Qur'an Printing Complex Developer Team,

We are preparing **Iqro**, an independent Quran reading and learning application. The current
technical staging version is available at <https://staging.iqro.forum>. The same first-party API
is designed for our web application, future iOS/Android applications, and Telegram Mini App.

For our production release, we want to use only an official, verifiable source package issued
directly by the King Fahd Glorious Qur'an Printing Complex. We do not want to rely on an
unofficial mirror or a third-party PDF.

Could you please provide the official download link or access procedure for the current
**Madinah Mushaf, Hafs ʿan ʿAsim** production package containing, where available:

1. the complete 604-page vector artwork or another official page-image master suitable for
   websites and smart applications;
2. the official Uthmanic Hafs Quran text/data package in JSON, CSV, SQL, XML, or equivalent
   formats, together with the required fonts;
3. page, surah, ayah, juz, hizb, and line mapping data;
4. the user manual, release/version identifier, original filenames, file sizes, and official
   checksums;
5. the applicable license/terms and the exact attribution wording and links required in the
   application.

We also request written confirmation for this limited technical use:

- Quran text and artwork will not be edited or altered;
- page artwork may be converted deterministically to WebP only for browser/mobile delivery;
- immutable generated assets may be hosted in our private Cloudflare R2 bucket and delivered
  through our first-party CDN hostname;
- content will be displayed only inside Iqro's first-party web, native mobile, and Telegram
  Mini App experience;
- no Quran dataset, raw source package, public content feed, or third-party API will be sold or
  redistributed;
- source and attribution will be displayed publicly at
  <https://staging.iqro.forum/en/sources> and in the production application;
- the initial release is free; please tell us whether future donations, subscriptions, or
  advertising require additional permission.

Please also tell us whether a separate signed license or scholarly/editorial review by the
Complex is required before public production launch.

- Developer/app owner: **[FULL LEGAL NAME / ORGANIZATION]**
- Project email: **iqro.forum@gmail.com**
- Privacy Policy: <https://staging.iqro.forum/en/privacy>
- Terms of Use: <https://staging.iqro.forum/en/terms>
- Sources and licenses: <https://staging.iqro.forum/en/sources>

Thank you.

## Что сохранить после ответа

- исходное письмо и ответ как `.eml` или PDF в закрытом evidence storage;
- имя/роль ответившего, дату, subject и message/thread ID;
- официальный download URL, redirect chain, filename, размер и SHA-256 каждого пакета;
- отдельную неизменяемую копию применимых terms/manual;
- точный attribution и любые ограничения;
- решение: `approved`, `separate license required`, `changes required` или `rejected`.

Файлы из ответа сначала сохраняются как неизменяемый upstream artifact. Из них создаётся новая
версия dataset; существующий `madani-hafs@1.0.2` не перезаписывается.
