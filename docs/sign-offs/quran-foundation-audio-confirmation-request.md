# Quran.Foundation audio use confirmation request

Дата подготовки: 25 августа 2026 года.

Назначение: получить письменное подтверждение конкретной streaming-схемы Iqro. В письмо нельзя
вставлять client secret, access token, внутренние URL или другие credentials.

Запрос отправляется через контакт, указанный в актуальных
[Quran.Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/)
или Developer Console. API credentials и Connected Apps listing — разные процессы: credentials
управляются в Developer Console, а listing проходит отдельный ручной review по правилам
[Connected Apps](https://api-docs.quran.foundation/docs/connected-apps/).

## Перед отправкой

Заменить только поля в квадратных скобках:

- `[FULL LEGAL NAME / ORGANIZATION]`;
- `[ACCOUNT EMAIL]` — email аккаунта в Developer Console;
- `[PUBLIC PRIVACY URL]` и `[PUBLIC TERMS URL]`;
- `[PRODUCTION URL]`, если он уже существует.

Не заменять техническое описание более широкой формулировкой: ответ должен относиться именно к
нашей ограниченной схеме без rehosting и offline redistribution.

## Готовый текст

**Subject:** Written confirmation request — Quran.Foundation recitation streaming in Iqro

Hello Quran.Foundation Developer Relations team,

We are preparing the public Web MVP of **Iqro**, a Quran reading and learning application.
Our current staging application is available at <https://staging.iqro.forum>. The planned
production web origin is `[PRODUCTION URL]`. The same first-party backend API is designed to
support our future iOS/Android application and Telegram Mini App.

We would like written confirmation that the following use of Quran.Foundation chapter-reciter
audio is permitted under the current Developer Terms:

1. Our backend uses production Content API credentials stored only in the server environment.
2. The application displays reciter and chapter metadata and streams the official audio URL
   only inside our first-party web, mobile and Telegram Mini App user experience.
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
- Is a five-day metadata refresh schedule acceptable for these chapter-reciter resources?
- Do you require any additional review before we enable three reciters in production?

We can provide architecture diagrams, API endpoints used, screenshots and the exact reciter IDs
without sharing secrets.

- Developer/app owner: `[FULL LEGAL NAME / ORGANIZATION]`
- Developer Console account: `[ACCOUNT EMAIL]`
- Privacy Policy: `[PUBLIC PRIVACY URL]`
- Terms of Use: `[PUBLIC TERMS URL]`

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
