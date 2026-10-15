# Аудит производительности и UX: web, API, Android/iOS, доставка

Дата: 15 октября 2026 года. Baseline: `7c52066` (ветка `codex/notes-unified-reading`).

## Область и итог

Проверены четыре слоя: Next.js-клиент (`services/web`), Django API
(`services/backend`), Flutter-клиент для Android и iOS (`clients/iqro_mobile`),
инфраструктура доставки (`ops/gateway`, `compose.production.yaml`, CI).
Это аудит исходного кода с локальными проверками и замерами числа SQL-запросов.
Реальный production-трафик, устройства, Lighthouse на текущем HEAD и полная сборка
не запускались. Всё, что требует подтверждения на устройстве или в production,
помечено как «предположение».

**Итог.** Кодовая база качественная: lint, typecheck и тесты зелёные, архитектура
продумана (курсорная пагинация, edge-кэш с purge, local-first мобильный клиент,
жёсткие production-контейнеры). Но в каждом слое есть несколько точечных проблем,
которые заметно бьют по скорости и надёжности. Почти все они исправляются локально,
без переписывания архитектуры.

Главные проблемы:

1. **Web не использует ISR.** Корневой layout читает `headers()` и `cookies()`,
   поэтому ни одна HTML-страница не пререндерится, а `revalidate` в 12 файлах не действует.
2. **Production легко перегрузить.** API даёт 10 одновременных запросов на весь сервер,
   нет rate limit и пула соединений с БД, а единственный Redis без `maxmemory` обслуживает
   брокер, троттлинг и кэши.
3. **Шрифты в production ломаются.** Google Fonts не попадают в production-CSS, CSP
   на gateway блокирует шрифт Nastaleeq, а мобильный клиент рисует Усмани системным `serif`.
4. **Мобильный клиент лишний раз перестраивает экраны.** Home и мини-плеер перестраиваются
   на каждом тике позиции аудио, Мусхаф не готовит соседние страницы, а интро-видео
   задерживает каждый холодный старт примерно на 5 секунд.
5. **Каталоги обрезаются первой страницей.** Чтецы и записи (web и mobile) и закладки (web)
   загружаются только первой страницей.

Код приложения в рамках аудита не изменялся.

## Результаты проверок

| Слой | Проверка | Результат |
|---|---|---|
| Web | `npm run typecheck` / `npm run lint` | pass / pass, 0 проблем |
| Web | `test:public-contracts`, `test:mushaf`, `test:cache` | 16/16, 12/12, 5/5 |
| Web | `node --test lib/dua-topics.test.ts` | 3/3, тест не подключён ни к одному npm-скрипту |
| API | `ruff check` / `mypy --strict` | pass / pass (278 файлов) |
| API | `ruff format --check` | **fail**: `audio/variant_resolver.py` |
| API | `pytest` на SQLite без coverage gate | 850 passed, 7 skipped |
| Mobile | `flutter analyze` (Flutter 3.41.4) | No issues found |
| Mobile | `flutter test test/app test/core test/features` | 535 passed (`test/integration` не запускался) |

Число SQL-запросов, измеренное через `CaptureQueriesContext`:

| Endpoint | Запросов |
|---|---|
| список аятов суры | 3 + N (по 1 на аят; Аль-Бакара ≈ 289) |
| `variant-ayah`, `variant-track` | 8 |
| страница QF-мусхафа | 5, и для 200, и для 304 |
| `/api/schema` | 184–505 мс CPU на запрос, ≈300 КБ |

Размер первого JS (сборка `.next` от 10.10, за 4 минуты до HEAD):

| Маршрут | Raw | Gzip |
|---|---|---|
| `/quran` | 793 КБ | 239 КБ |
| минимальный маршрут | — | 215 КБ |
| общий CSS | 113 КБ | 20,6 КБ |

## Приоритеты (сквозной план)

Колонки: **Эффект** — что получит пользователь, **Объём** — оценка трудозатрат.

### Неделя 1: быстрые исправления, по 1–3 часа каждое

| # | Что | Слой | Эффект |
|---|---|---|---|
| 1 | Добавить `https://static-cdn.tarteel.ai` в `font-src` gateway и тест на синхронность CSP | infra | Nastaleeq-мусхаф заработает в production |
| 2 | Перевести Inter/Amiri на `next/font/google` и убрать `@import` | web | правильная арабская типографика |
| 3 | `gzip on` на gateway для JSON/HTML/CSS/JS | infra | JSON меньше в 4–8 раз |
| 4 | `maxmemory` + политика для Redis; web-cache вынести в отдельный инстанс | infra | бэкенд не упадёт из-за OOM-kill Redis |
| 5 | `limit_req` на `/api/` и HTML, `proxy_read_timeout 30s` | infra | один клиент не займёт все слоты |
| 6 | `timeout` для SMTP | API | регистрация не блокирует воркеры |
| 7 | Исправить N+1 в `AyahSerializer.get_pages` | API | ≈289 → 3 запроса на суру |
| 8 | Позиция аудио: throttle вместо debounce при сохранении | mobile | «продолжить с места» после убийства процесса |
| 9 | `select` для подписок на аудио в Home и мини-плеере, позицию вынести в отдельный провайдер | mobile | меньше CPU и батареи при прослушивании |
| 10 | Кэшировать `ThemeData`, добавить `==` в `IqroColors`, убрать лишние `watch` в корне | mobile | без полных перестроек приложения |
| 11 | Интро-видео только на первом запуске, пропуск по тапу | mobile | холодный старт быстрее на 4–5 с |
| 12 | Cookie локали ставить только при изменении | web | HTML можно кэшировать |
| 13 | Ужать `iqro-wax-seal.png` / `iqro-logo.png` (2,7 МБ) и `startup.mp4` (5,3 МБ) | web+mobile | быстрее LCP, меньше APK/IPA и RAM |
| 14 | `ruff format` для `variant_resolver.py` | API | зелёный `make backend-check` |

### Недели 2–4: основные улучшения

| # | Что | Слой |
|---|---|---|
| 15 | Брать локаль из `params` в `app/[locale]/layout.tsx`, чтобы включить ISR | web |
| 16 | Серверная предзагрузка данных для `/quran`, `/`, `/audio` (по образцу `dua/page.tsx`), не блокировать первую страницу на индексе | web |
| 17 | Пул соединений Django (`OPTIONS["pool"]`) или pgbouncer, затем поднять конкурентность до 12–16 на воркер | API+infra |
| 18 | Денормализовать сводку `RecitationEdition` (counts, `timings_complete`) | API |
| 19 | Ранние ETag и `immutable` для версионированного контента; манифесты собирать при publish | API |
| 20 | Пагинация по `next` для чтецов, записей и закладок (web и mobile) | web+mobile |
| 21 | Мусхаф: `allowImplicitScrolling`, keepAlive ±2 страницы, `precacheImage`, кэш проверенных word-images | mobile |
| 22 | Бандлить шрифт KFGQPC Uthmanic HAFS для Reader, дуа и заучивания | mobile |
| 23 | iOS: `PrivacyInfo.xcprivacy` для Runner и виджета, исключить скачанный контент из iCloud backup | iOS |
| 24 | Разделить i18n-словарь по локалям (≈35 КБ gz с каждого маршрута) | web |
| 25 | Sentry/Crashlytics + web-vitals RUM | все |

### Далее

PWA-оффлайн для web, ночной режим Мусхафа, `Semantics` для текста Мусхафа,
непрерывное чтение и next/prev в медиа-контролах, адаптация под iPad,
nginx-микрокэш HTML, сборка образов в CI вместо production-хоста.

---

## 1. Инфраструктура и доставка

### 1.1 Высокий: один Redis на пять ролей, без `maxmemory`

[`compose.production.yaml:112`](../compose.production.yaml): `redis-server --appendonly yes --save 60 1`,
`mem_limit: 384m`, `maxmemory` не задан. Cache, throttle, broker, result и web ISR-кэш
используют один инстанс (`services/backend/.env.production.example:54-58`).

Web-кэш хранит HTML+RSC в base64 без сжатия на 24 часа
([`cache/shared-store.cjs:173`](../services/web/cache/shared-store.cjs),
[`cache/serialization.cjs:6`](../services/web/cache/serialization.cjs)). Только в sitemap
около 25 тысяч страниц аятов на редакцию.

Предположение: обход сайта краулером переполнит 384 МБ. OOM-kill уронит одновременно
Celery, троттлинг и все кэши. `docs/operations.md:163-166` сам требует задать `maxmemory`.

**Рекомендации:**
- web-cache держать в отдельном Redis: `--maxmemory 256mb --maxmemory-policy allkeys-lru --save "" --appendonly no`;
- broker и throttle: `maxmemory` около 75% лимита и `noeviction`;
- записи кэша сжимать (zlib/brotli).

### 1.2 Высокий: CSP gateway блокирует шрифт Nastaleeq

Gateway скрывает CSP от Next (`ops/gateway/default.conf:61`) и ставит свой
([`security-headers.conf:1`](../ops/gateway/security-headers.conf)). В нём `font-src` без
`https://static-cdn.tarteel.ai`, а в [`next.config.mjs:16`](../services/web/next.config.mjs)
этот хост есть и используется в `lib/quran-font.ts:63`. Тест `ops/gateway/test_config.py`
проверяет только префикс строки CSP.

**Рекомендации:** держать один источник CSP; добавить тест, что каждый хост из
`isAllowedQuranFontUrl` есть в CSP gateway.

### 1.3 Высокий: 10 одновременных API-запросов на весь production

В [`compose.production.yaml:33-34`](../compose.production.yaml) заданы 2 воркера по 5 запросов.
`compose.staging.budget.yaml` прямо фиксирует, что при таком лимите холодная загрузка
ридера отклоняется. Сверх лимита uvicorn отвечает голым 503 без `Retry-After`. Лимит
выведен из числа соединений PostgreSQL, потому что в
[`settings/production.py:21`](../services/backend/src/quran_backend/settings/production.py)
задан `CONN_MAX_AGE=0`, а пулера нет.

**Рекомендации:**
- встроенный пул Django 6 (`OPTIONS["pool"]` с `psycopg[pool]`) или pgbouncer в transaction mode;
- после этого поднять конкурентность до 12–16 на воркер и прогнать mixed capacity.

Пул заодно убирает fork и SCRAM-аутентификацию на каждом запросе.

### 1.4 Высокий: нет сжатия и rate limit

В `ops/gateway/*.conf` нет ни `gzip`, ни `limit_req`; в Django нет `GZipMiddleware`.
Сжатие есть только в staging-Caddy. Ключ кэша содержит весь `$request_uri`, поэтому
случайный query-параметр обходит edge-кэш.

**Рекомендации:**
- `gzip on; gzip_proxied any; gzip_types application/json text/css application/javascript image/svg+xml;`
- `limit_req_zone $binary_remote_addr` (около 20 r/s, burst 40) и `limit_conn`;
- белый список аргументов в ключе кэша;
- `error_page 503` с problem+json и `Retry-After`;
- закоммитить конфиг production edge (TLS, h2/h3).

### 1.5 Средний: edge-кэш почти не работает для браузеров

Любая Cookie означает bypass кэша (`default.conf:17-25`). При этом
[`proxy.ts:37`](../services/web/proxy.ts) ставит `quran_locale_v1` на каждый ответ.
Регулярка кэшируемых путей (`default.conf:87`) не покрывает `variants/`, `dua/`,
`calendar/` и `site/`. Кэш занимает 24 МБ на tmpfs и обнуляется при рестарте.
`LocaleMiddleware` добавляет `Vary: Accept-Language` к публичным ответам, которые от языка не зависят.

**Рекомендации:**
- учитывать в bypass только сессионные cookie;
- расширить регулярку;
- вынести кэш на volume размером 256–512 МБ;
- убрать `Accept-Language` из `Vary` для `/api/`.

### 1.6 Средний: прочее по инфраструктуре

- **Логи gateway.** nginx пишет access/error log в файлы на tmpfs 8 МБ, а не в stdout:
  логирование молча остановится. Нужен JSON-формат с `$request_time`,
  `$upstream_cache_status` и request-id.
- **PostgreSQL.** Не настроен: `shared_buffers` 128 МБ по умолчанию при лимите 1,5 ГБ.
  Нет `pg_stat_statements`, `log_min_duration_statement`, `stop_grace_period`.
- **Healthcheck и самовосстановление.**
  - Healthcheck web делает полный SSR лендинга каждые 10 секунд.
  - Unhealthy-контейнеры не перезапускаются.
  - У `worker` и `beat` healthcheck нет.
- **Деплой.** Образы собираются прямо на production-хосте (`Makefile:133`): сборка
  конкурирует с трафиком, а единственные реплики дают простой.
- **Keepalive.** nginx держит соединения 60 с, upstream — около 5 с. Возможны
  спорадические 502 на POST (предположение).
- **Next.js.** `/_next/static` проксируется в Node без кэша на gateway; сжатие тоже
  делает Node.
- **Наблюдаемость.** Нет Sentry/Crashlytics, web-vitals RUM, метрик nginx и Next.
- **CI.** Не запускает `test:mushaf`, `test:public-contracts` и `dua-topics.test.ts`.
  Lighthouse-бюджет не включает `/quran` и `/audio`.
- **Гигиена репозитория.** В корне отслеживается
  `dd3bd61507d2453391c47b67dff89c67.mp4`; это копия `startup.mp4`, файл можно удалить.
  Рабочее дерево занимает около 12 ГБ (`.dev`, `tmp`, `backups`, `clients/build`).

## 2. API (Django)

### 2.1 Высокий: N+1 в `AyahSerializer.get_pages`

[`quran/serializers.py:108-113`](../services/backend/src/quran_backend/modules/quran/serializers.py):
`.order_by().values_list().distinct()` игнорирует prefetch из `selectors.py:54`. Получается
1 запрос на каждый аят: для Аль-Бакары около 289.

**Рекомендация:** `sorted({m.page.number for m in obj.page_mappings.all()})` с
`Prefetch(... select_related("page"))`.

### 2.2 Высокий: каталог чтецов и variant-endpoint'ы считают агрегаты на лету

[`audio/selectors.py:79-113`](../services/backend/src/quran_backend/modules/audio/selectors.py)
делает три `COUNT(DISTINCT)` по трекам и сегментам и проверку «114 сур» до `LIMIT`.
`variant-ayah` и `variant-track` выполняют по 8 запросов, а `resolve_ayah` грузит всю суру
ради одного аята (`variant_resolver.py:603-620`).

**Рекомендации:**
- денормализовать сводку (`track_count`, `timed_ayah_count`, `timings_complete`, `delivery`)
  в `RecitationEdition` и пересчитывать её при publish/sync;
- добавить `variants/` в кэшируемые пути gateway.

Это же снимает стоимость пунктов из [аудита 12.10](application-audit-2026-10-12.md).

### 2.3 Высокий: HTTP-кэш не экономит работу сервера

[`core/public_api.py:32-48`](../services/backend/src/quran_backend/modules/core/public_api.py)
считает ETag после полного view и сериализации, поэтому 304 стоит столько же запросов, сколько 200.
Cache-Control одинаковый для всего (`max-age=300`).

**Рекомендации:**
- для версионированного контента (страницы мусхафа, манифесты, аудио по версии) ставить
  `max-age=31536000, immutable` с версией в URL;
- для остального считать ETag заранее из `checksum` активной версии;
- офлайн-манифесты (около 680 КБ, около 65 мс CPU) собирать при publish и отдавать как
  неизменяемые файлы.

### 2.4 Высокий: синхронный SMTP без таймаута

[`accounts/email_auth.py:108`](../services/backend/src/quran_backend/modules/accounts/email_auth.py)
вызывает `send_mail` в запросе, а в `MAILERS.OPTIONS`
([`settings/base.py:409`](../services/backend/src/quran_backend/settings/base.py)) нет `timeout`.
Зависший SMTP навсегда занимает один из 10 слотов.

**Рекомендации:** задать `"timeout": 10`, отправку перенести в Celery.

### 2.5 Средний: прочее по API

- **Схема OpenAPI.** `/api/schema` публичный и генерируется на каждый запрос (около 190 мс CPU).
  Лучше собирать при сборке или закрыть в production.
- **`statement_timeout`.** Не задан: тяжёлые запросы продолжаются после 504 у клиента.
- **Celery.**
  - Одна очередь: синхронизации QF делят слоты с web-push.
  - Нет `task_time_limit`, `visibility_timeout`, `ignore_result`.
- **Sync push.** `select_for_update` и `count()` выполняются на каждую операцию батча
  (`reading/services.py:263,355`); pull читает с `FOR UPDATE`.
- **QF-мусхафы.**
  - `page_assets.count()` выполняется дважды на страницу.
  - `apply_qul_layout` считается дважды.
  - Prefetch тянет неактивные публикации.
- **Тафсир и перевод.** Отдаются целиком на суру и тянут неиспользуемый `source_text`.
  Нужны диапазоны аятов и `.defer("source_text")`.
- **Единообразие ответов.** Списки отдаются в двух формах: голый массив и
  `{next, results}`. 410 и 503 приходят не в формате problem+json. `type` ведёт на
  `api.quran.example`.
- **Индексы и сортировка.**
  - Для курсора закладок нет индекса `(user, -updated_at, -id)`.
  - `Ayah.Meta.ordering` с join на `Surah`.

## 3. Web (Next.js)

### 3.1 Высокий: всё приложение динамическое, ISR не работает

[`app/layout.tsx:24,33`](../services/web/app/layout.tsx) вызывает `requestLocale()`, а тот читает
`headers()` и `cookies()` ([`lib/server-locale.ts:11-20`](../services/web/lib/server-locale.ts)).
В `prerender-manifest.json` нет ни одной HTML-страницы. Вдобавок `proxy.ts` ставит
`Set-Cookie` на каждый ответ.

**Рекомендации:**
- `<html lang dir>` перенести в `app/[locale]/layout.tsx` и брать локаль из `params`;
- пути без префикса оставить редиректами;
- cookie ставить только при изменении.

**Эффект:** около 25 тысяч страниц аятов, дуа и чтецов становятся кэшируемыми; на кэш-хите
TTFB падает до минимума, а нагрузка на CPU web (измеренное узкое место в
`docs/capacity`) снижается.

### 3.2 Высокий: основные разделы рендерятся только на клиенте

`/`, `/quran` (≈2200 строк в одном компоненте), `/audio`, `/prayer`, `/profile`,
`/planner` реэкспортируют клиентские страницы, и SSR-HTML `/quran` содержит только
«Загрузка…». До показа мусхафа проходит цепочка: 239 КБ JS → гидрация → около 20 запросов →
шрифт с `display: block`. Рендер ждёт ещё и индекс стихов (`app/quran/page.tsx:2075`).

**Рекомендации:**
- серверная предзагрузка editions, surahs, mushafs и первой страницы через
  `lib/public-content.ts` (так уже сделано в `app/[locale]/dua/page.tsx:30`);
- juz, hizb и rub грузить при открытии навигации.

### 3.3 Высокий: Google Fonts не попадают в production

`@import url(fonts.googleapis.com…)` в [`app/globals.css:2`](../services/web/app/globals.css)
отсутствует в production-CSS (`.next/static/chunks/*.css`). Amiri и Inter не грузятся,
арабский текст отображается системным fallback, два `preconnect` в `layout.tsx` бесполезны.

**Рекомендация:** `next/font/google` (Amiri arabic+latin, Inter latin+cyrillic) через CSS-переменные.

### 3.4 Высокий: данные обрезаются первой страницей

**Чтецы и записи** загружаются только первой страницей (page_size 50):
- `app/audio/page.tsx:66` и `:100`;
- `components/MushafAudioPlayer.tsx:109`;
- `app/page.tsx:72`.

`api.getAllRecitations` уже есть, но используется только в заучивании.

**Закладки** тоже ограничены первой страницей:
- `app/quran/page.tsx:883` и `app/profile/page.tsx:177` берут только 50;
- при большем числе читалка считает аят несохранённым, а нажатие создаёт дубль.

### 3.5 Высокий: словарь всех 4 языков в каждом маршруте

`lib/i18n.ts` (194 КБ исходника, около 57 КБ gz) импортируется в клиентский `i18n-context.tsx`.

**Рекомендация:** JSON по локалям; провайдеру передавать только текущую локаль с сервера.

**Эффект:** около 15% first-load JS.

### 3.6 Средний: рендер и интерактивность

- **Ререндеры читалки.** `QuranContent` содержит около 60 `useState`; `memo` и
  `next/dynamic` не используются нигде. Каждая смена аята при воспроизведении и каждая
  секунда режима «после намаза» (`ReadingActivityTracker.tsx:146`) перерисовывают всю
  читалку и до 286 карточек.
  - **Рекомендации:** `memo` для страницы мусхафа и `AyahCard`, локальное состояние
    таймера, `content-visibility: auto`, рассмотреть `reactCompiler`.
- **Подсветка аята.** Привязана к `timeupdate` (около 250 мс), см.
  `SegmentedAudioPlayer.tsx:493`.
  - **Рекомендации:** `requestAnimationFrame` или таймер на конец сегмента.
- **Авторизация.** `auth-context.tsx:53` блокирует публичные данные на `POST /web-auth/refresh`;
  `value` контекста не мемоизирован.
- **Кэширование клиентских запросов.** Все GET идут с `cache: "no-cache"`
  (`lib/api.ts:1374`), включая неизменяемые каталоги.
- **Мелкая производительность.**
  - `tafsirForVerse` ищет через `Array.find`; нужен `Map`.
  - Видимый аят определяется через `getBoundingClientRect` по всем аятам; нужен
    `IntersectionObserver`.

### 3.7 Средний: UX, доступность, SEO

- **Состояния загрузки.** Нет ни одного `loading.tsx`: при переходах нет обратной связи.
- **LCP лендинга.**
  - Hero подключён через CSS `background-image` без preload.
  - `preload` стоит на PNG-логотипе весом 2,7 МБ, который выводится в 56 px.
- **Доступность.**
  - У арабского текста в текстовом режиме нет `lang="ar"` (`quran/page.tsx:1970`).
  - Мусхаф недоступен скринридеру: `aria-label` перекрывает текст.
  - 25 из 33 блоков `.alert` без `role="alert"` или `aria-live`.
  - Нет skip-link.
- **Текстовый режим.** Не следует за играющим аятом; smooth-scroll не учитывает
  `prefers-reduced-motion`.
- **Аудио.** Гонка при быстрой смене записи (`audio/page.tsx:134-147`).
- **SEO.**
  - `/`, `/quran` и `/audio` в sitemap с высоким приоритетом, но без контента в HTML.
  - Глубоких страниц дуа нет в sitemap.
  - `SITE_NAME` «Quran Platform» расходится с брендом IQRO.
- **PWA.**
  - Нет fetch-обработчика и офлайн-оболочки.
  - Иконка одна: PNG 512 px весом 480 КБ, нет вариантов 192 и maskable.
- **Навигация.** `/memorization` и `/planner` отсутствуют в matcher `proxy.ts`.

## 4. Мобильное приложение (Flutter, Android и iOS)

### 4.1 Высокий: перестройки на каждом тике позиции аудио

[`audio_controller.dart:481-506`](../clients/iqro_mobile/lib/core/audio/audio_controller.dart)
на каждом `positionStream` (16–200 мс) обновляет общее состояние.
[`home_screen.dart:49`](../clients/iqro_mobile/lib/features/home/home_screen.dart) и
[`mini_player.dart:38`](../clients/iqro_mobile/lib/features/audio/mini_player.dart) подписаны
на него целиком. Home живёт в `IndexedStack` под Мусхафом и пересчитывает весь дашборд.

**Рекомендации:**
- позицию вынести в отдельный `StreamProvider` (`createPositionStream(minPeriod: 200ms)`);
- в Home использовать `select`;
- на позицию подписывать только прогресс-бар.

### 4.2 Высокий: позиция прослушивания не сохраняется во время игры

`_schedulePersistence` (`audio_controller.dart:1979`) при каждом тике отменяет таймер
на 2 секунды, поэтому он не срабатывает. Если процесс убит во время воспроизведения,
позиция теряется.

**Рекомендации:** throttle раз в 10 секунд плюс сохранение на `AppLifecycleState.paused`.

### 4.3 Высокий: перестройка всего приложения при смене настроек

[`app.dart:215-216`](../clients/iqro_mobile/lib/app/app.dart) создаёт `IqroTheme.light()/dark()`
в каждом build. У `IqroColors` нет `==`, поэтому `ThemeData` всегда «новая».
Корень приложения подписан на `sessionProvider` и `reminderProvider`.

**Рекомендации:**
- `static final` темы и `==`/`hashCode` в `IqroColors`;
- в корне `select` по `themeMode` и `locale`, `ref.listen` вместо `watch`.

### 4.4 Высокий: листание Мусхафа

У `PageView` в [`mushaf_screen.dart:306`](../clients/iqro_mobile/lib/features/quran/mushaf_screen.dart)
нет `allowImplicitScrolling`. `mushafPageProvider` объявлен как `autoDispose`
([`providers.dart:580`](../clients/iqro_mobile/lib/app/providers.dart)), поэтому prefetch
только скачивает файл, а данные и декодированное изображение выбрасываются.
Каждая страница заново проходит DB → `jsonDecode` → decode → layout со спиннером.

В режиме word-images каждое открытие страницы даёт около 150 DB-запросов, полный SHA-256
файлов в UI-изоляте и декодирование без кэша (`quran_repository.dart:582-628`).

**Рекомендации:**
- `allowImplicitScrolling: true`;
- `keepAlive` окна ±2 страницы;
- `precacheImage(FileImage(...))`;
- in-memory реестр проверенных файлов: хеш проверять один раз после скачивания;
- декодирование с `targetWidth`.

### 4.5 Высокий: интро-видео на каждом холодном старте

Вход в приложение ждёт окончания видео
([`startup_gate.dart:44`](../clients/iqro_mobile/lib/core/startup/startup_gate.dart)):
5 секунд, watchdog до 12 секунд. `startup.mp4` весит 5,3 МБ, 1080×1920, со звуковой
дорожкой, хотя играется без звука.

**Рекомендации:**
- видео только на первом запуске или после обновления, пропуск по тапу;
- дальше статичный splash;
- перекодировать в 720p без аудио (≈1 МБ).

После этого станет заметна последовательная инициализация в `app_dependencies.dart:78-114`.
Её стоит распараллелить, а `notifications.initialize()` и `timezone` (`latest_10y`)
перенести после первого кадра.

### 4.6 Высокий: текст Корана рендерится системным `serif`

`fontFamily: 'serif'` используется в `reader_screen.dart:1152`, `mushaf_paper.dart:37`,
`iqro_theme.dart:139`, дуа и заучивании; блока `fonts:` в `pubspec.yaml` нет.
На iOS `serif` подменяется системным арабским шрифтом. Предположение: часть знаков
Усмани (малые высокие буквы, U+06E1, U+08F0) отобразится неверно.

**Рекомендация:** бандлить KFGQPC Uthmanic Script HAFS (с subsetting) и задать его явно.

### 4.7 Высокий (iOS): готовность к App Store

- **Резервное копирование.** Скачиваемый контент (`mushaf_pages`, `foundation_assets`,
  офлайн-пакеты до 3 ГБ) лежит в Application Support без `isExcludedFromBackup`. Это
  нарушает iOS Data Storage Guidelines и раздувает iCloud.
  - **Рекомендация:** MethodChannel для установки флага или `getApplicationCacheDirectory()`
    для стримингового кэша.
- **Privacy manifest.** Нет `PrivacyInfo.xcprivacy` ни у Runner, ни у widget extension,
  хотя виджет использует `UserDefaults(suiteName:)` — это required-reason API.
- **Аудиосессия.** Предположение: `VideoPlayerOptions(mixWithOthers: true)` интро-видео
  может оставить категорию AVAudioSession в mix-режиме. Тогда пропадут Now Playing и
  remote controls.
  - **Рекомендация:** повторно вызывать `session.configure(speech)` перед первым `play()`.

### 4.8 Средний: прочее по мобильному клиенту

- **Медиа-сессия.** Контекстное аудио (Мусхаф, дуа, заучивание) её не публикует: нет
  управления с экрана блокировки и foreground service на Android. Повторы заучивания
  в фоне могут прерываться (предположение).
- **Пагинация и кэш.** `AudioRepository` (`audio_repository.dart:36-40, 109-117`) не
  ходит по `next`; правильный helper уже есть в `dua_repository.dart`.
- **Рост кэша.**
  - `cache_entries`, `mushaf_pages/` и `foundation_assets/` растут без вытеснения.
  - `jsonDecode` больших записей кэша выполняется на UI-изоляте (`local_database.dart:185`).
- **Сеть.**
  - ETag не используется: параметр в `api_client.dart:94` есть, но никто его не передаёт,
    а 304 не обрабатывается.
  - Нет retry с jitter для GET.
- **Workmanager.** Колбэк намеренно пустой (см. комментарий в `background_work.dart:9-25`),
  но задача всё равно регистрируется каждые 6 часов на Android и как BGTask на iOS.
  Лучше не регистрировать её, пока она ничего не делает.
- **Медиа-контролы.** Нет next/prev и stop; нет автоперехода на следующую суру.
  Мусхаф играет только один аят.
- **Layout.**
  - Мини-плеер стоит на захардкоженном `bottom: 72` без учёта safe-area (`app_shell.dart:52`)
    и имеет фиксированную высоту 66. При крупном шрифте текст обрезается.
  - Предположение: на iPhone с home indicator плеер перекрывает контент.
- **Доступность Мусхафа.** Текст недоступен скринридеру (`CustomPaint` без `Semantics`).
- **Логотип.** PNG 1265×1244 (2,7 МБ, около 6 МБ RAM) декодируется ради иконок 24–40 px
  в 25 местах. Нужны варианты 1x/2x/3x и `cacheWidth`.
- **Ошибки.** Нет crash reporting и глобальных обработчиков (`FlutterError.onError`,
  `PlatformDispatcher.onError`).
- **Ночной режим.** Мусхаф всегда на светлой «бумаге», splash всегда светлый.
- **Android.**
  - Лишнее `ACCESS_FINE_LOCATION`, хотя запрашивается `LocationAccuracy.medium`.
  - Кнопка «назад» с любой вкладки закрывает приложение: вкладки переключаются через `go`.
- **Неиспользуемые зависимости.** `photo_view` и `just_audio_background` в `lib` не
  используются; конфликта с `audio_service` нет.
- **Мелочи.**
  - Не все списки ленивые (`favorites_screen.dart:136`, `dua_screen.dart:313`).
  - `FilterQuality.high` на Impeller.
  - На iPad нет ограничения ширины контента.

## Сильные стороны

- **Качество кода.** Lint, typecheck, mypy strict, `flutter analyze` чистые; около
  1400 тестов зелёные.
- **API.**
  - Курсорная пагинация без `COUNT(*)`.
  - Problem+json с `request_id`.
  - Таймауты на всех внешних вызовах.
  - Атомарные scoped-лимиты.
  - Edge-кэш с lock, stale и purge после публикации.
- **Медиа.** Аудио и растровые страницы идут через R2/CDN с immutable-кэшем, Range и ETag;
  есть контрактные тесты.
- **Production-контейнеры.** `read_only`, `cap_drop ALL`, non-root, лимиты ресурсов,
  multi-stage, `standalone` для Next.
- **Web.**
  - SEO-страницы сур, аятов и дуа: серверный рендер, `Promise.all`, JSON-LD, hreflang.
  - `MushafPageCache` с префетчем ±2 и LRU шрифтов.
  - Клавиатурная навигация и RTL.
- **Mobile.**
  - Local-first: SQLite в WAL, outbox-синхронизация, докачка с проверкой хеша.
  - Правильная конфигурация `audio_service` (foreground service `mediaPlayback`).
  - Аккуратный RTL, 4 локали, виджеты на обеих платформах.
  - R8 и shrinkResources, 120 Гц на iPhone.

## Метрики, по которым проверять результат

| Метрика | Как мерить | Цель |
|---|---|---|
| Web TTFB/LCP `/ru/quran/...` (ISR-страницы) | Lighthouse CI + web-vitals RUM | LCP < 2,5 с на 4G, TTFB < 200 мс на кэш-хите |
| INP на `/quran` при воспроизведении | RUM / Performance panel | < 200 мс |
| First-load JS | `route-bundle-stats.json` | −15–25% |
| p95 API публичного чтения | Prometheus histogram | < 150 мс, edge hit-ratio > 80% |
| 503 при capacity-тесте | `ops/load` mixed profile | 0 при целевой нагрузке |
| Холодный старт mobile | DevTools timeline / Crashlytics traces | < 1,5 с до интерактивного Home (не первый запуск) |
| Jank при листании Мусхафа | `flutter run --profile`, FrameTiming | < 1% кадров дольше 16 мс, без спиннера при листании |
| CPU во время прослушивания | Android Studio / Instruments | ×3–5 меньше перестроек виджетов |

## Что не проверялось

- Реальные устройства Android и iPhone, профилирование кадров и энергопотребления.
- Production-конфигурация внешнего TLS-proxy: в репозитории её нет.
- Свежая production-сборка web и Lighthouse на текущем HEAD.
- Время тяжёлых SQL-запросов на полном production-объёме.
- `flutter test test/integration` и полный CI с coverage gate.
