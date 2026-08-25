# Quran.Foundation audio use confirmation request

Дата подготовки: 25 августа 2026 года.

Статус: **не является обязательным production gate** для стандартной интеграции Iqro.
Актуальные Developer Terms уже разрешают показывать Quran.Foundation Content внутри
first-party приложения, включая обычную коммерческую модель приложения, пока сырой контент
не продаётся и не распространяется отдельно. Сохранённое внутреннее решение находится в
[license decision record](quran-foundation-audio-license-decision-2026-08-25.md).

Назначение этого письма: только дополнительное разъяснение, если Iqro захочет выйти за
стандартную схему — rehosting, offline redistribution, отдельный content feed/API или другое
не описанное Terms использование. Для текущего server-side streaming письмо отправлять не
требуется. В письмо нельзя вставлять client secret, access token, внутренние URL или другие
credentials.

Запрос отправляется на `developers@quran.com` с email, связанного с Developer Console. Этот
адрес опубликован в актуальных
[Quran.Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/).
API credentials и Connected Apps listing — разные процессы: credentials
управляются в Developer Console, а listing проходит отдельный ручной review по правилам
[Connected Apps](https://api-docs.quran.foundation/docs/connected-apps/).

## Перед отправкой

Заменить только поля в квадратных скобках:

- `[FULL LEGAL NAME / ORGANIZATION]`;
- `[ACCOUNT EMAIL]` — email аккаунта в Developer Console;
- текущие публичные staging legal URL уже подставлены; после production deployment их нужно
  заменить на production URL.

Не заменять техническое описание более широкой формулировкой: ответ должен относиться именно к
нашей ограниченной схеме без rehosting и offline redistribution.

## Готовый текст

**Subject:** Written confirmation request — complete Quran.Foundation recitation catalog streaming in Iqro

Hello Quran.Foundation Developer Relations team,

We are preparing the public Web MVP of **Iqro**, a Quran reading and learning application.
Our current staging application is available at <https://staging.iqro.forum>. The planned
production web origin is <https://iqro.forum>. The same first-party backend API is designed to
support our future iOS/Android application and Telegram Mini App.

These clients may use different first-party web origins or native deep-link identifiers, but
none of them will call the Quran.Foundation Content API directly or contain Quran.Foundation
credentials. All Content API access will originate from the same confidential backend/server
integration. We are not requesting Quran.Foundation OAuth or User API access in this letter;
if those features are added later, we will register every exact redirect URI and request the
required production scopes separately in Developer Console.

We would like written confirmation that the following use of the complete Quran.Foundation
chapter-reciter and ayah-by-ayah recitation catalog available to our production credentials is
permitted under the current Developer Terms:

1. Our backend uses production Content API credentials stored only in the server environment.
2. The application synchronizes the available reciter/recitation catalog, displays its metadata,
   and streams the official audio URL only inside our first-party web, mobile and Telegram Mini
   App user experience. We intend to support every resource permitted to our application,
   including additional qira'at/riwayat if and when they appear in that catalog.
3. We do not copy or rehost Quran.Foundation audio in Cloudflare R2 or on our application
   server.
4. We do not offer offline download, redistribution, a dataset, data feed, content package or
   public third-party API containing Quran.Foundation content.
5. Our public API returns the playback information only to these first-party clients as part of
   the application experience; credentials are never exposed to clients.
6. Cached Quran.Foundation metadata is refreshed at least every five days, and corrections,
   withdrawals and source updates are applied. We can shorten this interval if required.
7. We will provide public Privacy Policy, Terms of Use, support/security contacts and visible
   content attribution before launch.
8. The initial release may be free of charge. Future donations, subscriptions or advertising,
   if introduced, will not sell or redistribute Quran.Foundation content or raw API data.

Could you please confirm:

- Is this streaming model covered by the standard Developer Terms, or is a separate written
  content/commercial license required?
- May our backend return the official playback URL to our first-party clients, or must each
  playback URL be resolved in another way?
- What exact attribution text and links should be shown for recitations and metadata?
- Are there additional restrictions for Web, native mobile, or Telegram Mini App clients?
- Does this server-side Content API architecture require separate Quran.Foundation apps or
  credentials when we add these first-party clients, or may they all consume the same
  backend-proxied content service?
- Is a five-day metadata refresh schedule acceptable for these chapter-reciter resources?
- May we expose every chapter-reciter and ayah-by-ayah recitation resource available to our
  production credentials, subject to per-resource source attribution and our editorial checks?
- Does any resource, reciter, qira'ah or riwayah in the API have source-specific restrictions
  that are not represented in the API metadata?
- Do you require additional review before we progressively enable the full permitted catalog in
  production?

We can provide architecture diagrams, API endpoints used, screenshots and the exact resource IDs
without sharing secrets. We will initially ingest catalog entries as non-public drafts and publish
them only after source, riwayah compatibility, attribution and playback checks pass.

- Developer/app owner: `[FULL LEGAL NAME / ORGANIZATION]`
- Developer Console account: `[ACCOUNT EMAIL]`
- Privacy Policy: <https://staging.iqro.forum/en/privacy>
- Terms of Use: <https://staging.iqro.forum/en/terms>
- Providers: <https://staging.iqro.forum/en/providers>
- Sources and licenses: <https://staging.iqro.forum/en/sources>

Thank you.

## Как сохранить sign-off

После ответа создать новый immutable record и приложить:

- дату ответа и имя/роль отправителя, если они указаны;
- исходный subject и message/thread ID;
- сохранённый PDF или `.eml` в закрытом release evidence storage;
- краткое решение: `standard terms sufficient`, `additional license required` или `changes
  required`;
- обязательную атрибуцию и ограничения дословно, но без credentials;
- ссылку/ticket в audio acceptance record.

Само письмо не публикуется в репозитории, если оно содержит персональные или конфиденциальные
данные. В Git хранится только безопасное резюме решения.
