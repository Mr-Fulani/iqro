# KFGQPC official production source catalog request

Дата подготовки: 25 августа 2026 года.

## Кому отправить

- To: `developer@qurancomplex.gov.sa`
- CC: не использовать
- Отправитель: рабочий адрес проекта `fulani.dev@gmail.com`

`developer@qurancomplex.gov.sa` опубликован в официальном Quran Hafs guide и как support email
официального приложения. `info@qurancomplex.gov.sa` не ставить в копию: 25 августа 2026 года
их входной шлюз отклонил этот recipient с `550 5.7.1 XGEMAIL_0008 Command rejected`. Если
`developer@...` не ответит в течение пяти рабочих дней, переслать исходное письмо без изменения
на резервный `contact@qurancomplex.gov.sa`, опубликованный в официальном technical guide, и
приложить короткое пояснение о недоставленной копии. Секреты, API credentials и внутренние
серверные URL в письмо не добавлять.

## Что именно запрашивается

Нужен не произвольный PDF из стороннего зеркала, а полный актуальный каталог официальных
immutable source packages, доступных для web/mobile приложений:

1. полный Madinah Mushaf, Hafs ʿan ʿAsim, 604-page vector artwork или другой официальный
   page-image master, разрешённый для приложений;
2. все остальные официально доступные варианты/риваяты и их соответствующие text, font,
   page artwork и mapping packages, включая опубликованные на developer platform Warsh,
   Shu'bah, Qaloun, Al-Douri и Al-Sousi;
3. официальный Uthmanic text/data package каждого варианта в JSON/CSV/SQL/XML или эквивалентном
   формате и соответствующие fonts;
4. page, surah, ayah, juz, hizb и line mapping, если он входит в соответствующий пакет;
5. актуальный machine-readable inventory или способ узнавать о новых версиях и вариантах;
6. точное имя и номер версии, дата выпуска, исходный filename, размер и опубликованные
   checksums;
7. user manual, terms/license и требуемый attribution отдельно для каждого пакета;
8. письменное подтверждение допустимости неизменяющего технического преобразования page artwork
   в WebP, размещения immutable assets в Cloudflare R2/CDN и отображения в first-party Web,
   iOS/Android и Telegram Mini App.

## Готовое письмо

**Subject:** Request for the complete official Mushaf production source catalog and usage confirmation — Iqro

Hello King Fahd Glorious Qur'an Printing Complex Developer Team,

We are preparing **Iqro**, an independent Quran reading and learning application. The current
technical staging version is available at <https://staging.iqro.forum>. The same first-party API
is designed for our web application, future iOS/Android applications, and Telegram Mini App.

For our production release, we want to use only an official, verifiable source package issued
directly by the King Fahd Glorious Qur'an Printing Complex. We do not want to rely on an
unofficial mirror or a third-party PDF.

Could you please provide the official download links or access procedure for the complete
current catalog of Mushaf and riwayah production packages that the Complex permits in web and
smart applications? We need **Madinah Mushaf, Hafs ʿan ʿAsim**, and all other officially
available variants, including the Warsh, Shu'bah, Qaloun, Al-Douri and Al-Sousi resources
currently described on the developer platform.

For each available variant, could you please provide, where available:

1. the complete vector artwork or another official page-image master suitable for websites and
   smart applications;
2. the corresponding official Uthmanic Quran text/data package in JSON, CSV, SQL, XML, or
   equivalent formats, together with the required fonts;
3. page, surah, ayah, juz, hizb, and line mapping data;
4. the user manual, release/version identifier, original filenames, file sizes, and official
   checksums;
5. the applicable license/terms and the exact attribution wording and links required in the
   application;
6. a current catalog/inventory or notification method that lets us discover new variants,
   corrections and releases without relying on unofficial mirrors.

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
- Project email: **fulani.dev@gmail.com**
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

Файлы из ответа сначала сохраняются как неизменяемые upstream artifacts. Каждый риваят получает
отдельные edition code и version; варианты никогда не объединяются в один dataset. Из официальных
пакетов создаются новые datasets; существующий `madani-hafs@1.0.2` не перезаписывается.
