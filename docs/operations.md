# Production operations

Этот runbook покрывает наблюдаемость backend, резервные копии PostgreSQL, ограниченный
нагрузочный smoke-тест и staged capacity harness. Команды выполняются из корня репозитория.

## Operational health и Prometheus

Liveness и readiness остаются публичными:

- `/api/v1/health/live` проверяет процесс;
- `/api/v1/health/ready` проверяет PostgreSQL и Redis.

Состояние внешней Quran.Foundation намеренно вынесено отдельно: её временный сбой не должен
выключать уже загруженный каталог. Защищённые endpoint'ы:

- `/api/v1/health/operations` — JSON и HTTP 503 при просроченной/ошибочной синхронизации;
- `/api/v1/metrics` — Prometheus text exposition.

Формат генерируется официальным
[Prometheus Python client](https://prometheus.github.io/client_python/), без process-local
счётчиков, поэтому он одинаково работает с несколькими Gunicorn workers.

Создайте независимый секрет и добавьте его в production secret store как
`QURAN_OPERATIONS_TOKEN`:

```bash
openssl rand -hex 32
```

Не передавайте этот токен во frontend и не коммитьте его. Мониторинг должен отправлять:

```text
Authorization: Bearer <QURAN_OPERATIONS_TOKEN>
```

Если токен не настроен, endpoint'ы отвечают 404. Порог свежести задаётся
`QF_AUDIO_STALE_AFTER_HOURS` (по умолчанию 168 часов) и не может быть короче интервала
`QF_AUDIO_REFRESH_DAYS`.

Минимальные alerts:

- Prometheus target недоступен (`up == 0`);
- сумма `quran_foundation_audio_sync_states` со status `stale`, `failing` или
  `never_synced` больше нуля;
- `quran_foundation_audio_sync_max_consecutive_failures > 0`;
- `quran_platform_catalog_items{kind="mushaf_pages"} < 604`;
- `quran_platform_catalog_items{kind="ayahs"} < 6236`;
- `quran_platform_catalog_items{kind="audio_recitations"} < 1`.

Последние три порога подходят текущему Madani Hafs dataset. При подключении другого издания
их нужно пересмотреть.

## Content cache и sitemap

Каталог и глубокие web-маршруты Quran, чтецов и декламаций получают данные server-to-server
через `BACKEND_INTERNAL_URL`. В production Compose это `http://backend:8000`; публичный browser
API по-прежнему идёт через gateway. В запрос не передаётся `Authorization`: backend publication
selectors являются единственной границей, решающей, какие Quran edition/version и полные
streamable audio releases доступны поисковому индексу.

Data-driven страницы рендерятся сервером по запросу: общий layout читает request locale из
proxy header/cookie, поэтому страницы намеренно не объявляются on-demand ISR через пустой
`generateStaticParams`. Next.js fetch cache обновляет опубликованный Quran/audio-контент не
реже одного раза в час и помечает запросы тегами edition/surah/ayah или
reciter/recitation/track. Публикация,
активация и отзыв версии после commit автоматически ставят Celery-задачу
`core.notify_web_content_change`. Она подписанным внутренним POST инвалидирует соответствующие
data tags, route cache и versioned sitemap. Временные сетевые/5xx ошибки повторяются с backoff;
4xx считается ошибкой конфигурации или контракта и требует вмешательства. Часовой TTL остаётся
страховочной границей, если webhook исчерпал retry. Персональные маршруты в этот кэш не входят.

Один и тот же случайный `WEB_CONTENT_REVALIDATION_SECRET` длиной от 32 символов передаётся
backend/worker и web через secret store; в логах и URL его быть не должно. Internal URL по
умолчанию в Compose — `http://web:3000/api/internal/content-revalidation`. Endpoint не принимает
произвольные cache tags/paths: только allowlisted Quran/audio события с валидными edition,
content version и UUID. Без корректного секрета он отвечает 404.

Текущий single-web профиль использует стандартный filesystem cache Next.js. Перед запуском
второй web-реплики необходимо подключить общий cache handler и Redis-backed координацию tag
timestamps (`updateTags`/`refreshTags`/`getExpiration`): стандартная on-demand invalidation
локальна для одного инстанса. Если CDN начнёт кэшировать HTML/RSC или public JSON поверх
Next.js, тот же publication event обязан purge'ить CDN-варианты; до появления purge adapter
gateway не должен добавлять для них независимый edge TTL. Immutable media кэшируется отдельно
в media CDN и не зависит от ISR webhook.

`/sitemaps/quran/sitemap.xml` ссылается на child sitemap с edition и активной content version в
URL. `/sitemaps/audio/sitemap.xml` делает то же для каждой опубликованной декламации. Child
sitemap перечисляют только доступные через public API сущности и возвращают 404 для draft,
withdrawn, non-streaming, incomplete или уже неактивной версии. Индексы указаны в `robots.txt`.
После публикации или отзыва контента проверьте:

```bash
curl --fail https://example.org/sitemaps/quran/sitemap.xml
curl --fail https://example.org/ru/quran/madani-hafs/surah/1
curl --fail https://example.org/sitemaps/audio/sitemap.xml
curl --fail https://example.org/ru/audio/reciters
```

При ротации секрета сначала обновите worker/backend и web как одну rollout-группу, затем
повторно отправьте последнее publication event либо дождитесь часового TTL. Алерт обязателен
на окончательно failed `core.notify_web_content_change` и на расхождение active content version
между public API, страницей и sitemap.

Ошибка upstream не подменяется пустым успешным sitemap: endpoint отвечает 503, чтобы crawler
повторил запрос позднее и не счёл исчезновение контента штатным удалением.

## Legal и public contacts

Web публикует locale-prefixed `/privacy`, `/terms`, `/contacts` и `/sources`. Последний маршрут
строит актуальный список только из опубликованных Quran editions и streamable audio releases,
показывает content version, источник, правообладателя и лицензию, но не раскрывает media URL.
Footer и основной sitemap ссылаются на все четыре страницы.

Production Compose не стартует без заполненных `LEGAL_ENTITY_NAME`, `LEGAL_CONTACT_EMAIL`,
`SECURITY_CONTACT_EMAIL`, `LEGAL_POSTAL_ADDRESS`, `LEGAL_JURISDICTION` и
`LEGAL_EFFECTIVE_DATE`. Значения-заглушки из `.env.production.example` запрещены для staging
sign-off и production. Перед публичным запуском юрист должен сверить фактического оператора,
правовые основания, поставщиков/страны обработки и трансграничные механизмы с реальным
deployment; тексты в репозитории не заменяют такую проверку. Privacy notice построен так, чтобы
явно перечислить оператора и контакты, категории данных, цели/основания, получателей,
передачи, сроки и права пользователя — по структуре
[GDPR Article 13](https://eur-lex.europa.eu/eli/reg/2016/679/) и официального перечня
[KVKK Aydınlatma Yükümlülüğü](https://www.kvkk.gov.tr/Icerik/2033/Aydinlatma-Yukumlulugu-).

После rollout проверьте четыре локали, рабочие `mailto:`, якорь `/profile#feedback`, а также что
`/sources` совпадает с public API и не содержит прямых audio URLs.

## Security headers

Next.js ставит одинаковую базовую политику и при прямом доступе, а gateway скрывает upstream
варианты и выдаёт один нормализованный набор для web, API, admin, static и media: CSP,
`frame-ancestors 'none'`/`X-Frame-Options: DENY`, MIME/referrer/permissions policy, COOP и HSTS.
Production CSP не содержит `unsafe-eval`; `unsafe-inline` пока сохранён для Next.js hydration,
JSON-LD и существующих inline styles, чтобы не отключать ISR/SSG ради per-request nonce. После
перехода на self-hosted fonts и отказа от inline styles можно оценить experimental SRI/hash CSP.

`geolocation` разрешена только собственному origin для расчёта намаза; camera, microphone,
payment и USB запрещены. Quran/audio media разрешены по HTTPS, но исполнение script — только с
собственного origin. Отдельный Telegram Mini App следует публиковать на отдельном origin с
точным allowlist `frame-ancestors`; ослаблять публичный web до произвольного embedding нельзя.

HSTS начинает защищать пользователя только после реального HTTPS-ответа. До включения
`includeSubDomains` убедитесь, что все поддомены обслуживаются по TLS; preload намеренно не
добавлен на gateway без отдельного решения владельца домена.

## Web Lighthouse budgets

Web CI запускает официальный Lighthouse на том же standalone entrypoint, который используется
в production-образе. Runner сам собирает bundle с детерминированным mock publication API и
проверяет шесть маршрутов: landing RU/EN/AR/TR и опубликованную суру RU/AR. До измерения он
отдельно подтверждает ожидаемые `lang` и `dir`, поэтому арабский RTL входит в blocking gate, а
не остаётся визуальной договорённостью.

Пороги находятся в `services/web/lighthouse-budget.json` и ограничивают категории performance,
accessibility, best practices и SEO, FCP/LCP/TBT/CLS, размеры ресурсов и число запросов.
Локальный полный запуск:

```bash
cd services/web
npm run test:lighthouse
```

Для диагностики одного шаблона задайте точный route, например
`LIGHTHOUSE_ROUTE=/ar/quran/madani-hafs/surah/1 npm run test:lighthouse`. Скрипт выполняет
production build сам; предварительный `npm run build` не требуется. Это лабораторный regression
gate, а не доказательство полевых Core Web Vitals: после deployment остаются обязательными
RUM/Search Console и проверка реального CDN, TLS и backend latency.

Playwright также имеет два независимых режима. `npm run test:e2e` проверяет быстрый dev server;
`npm run test:e2e:production` пересобирает и запускает standalone bundle с тем же mock API и
повторяет все browser-сценарии. Оба режима блокируют Web CI. Production режим защищает от
расхождений build-time rewrites, static asset packaging, SSR/404 и metadata между `next dev` и
реальным deployable artifact. Он не заменяет smoke против настоящего staging API.

## Managed media CDN contract

Решение по provider и переносимости описано в
[ADR 0001](adr/0001-managed-media-object-storage-cdn.md). Перед публикацией managed audio или
другого крупного immutable asset скопируйте `ops/media/manifest.example.json`, перечислите
точные production/staging origins и заполните URL, размер, MIME type и при наличии уже
зафиксированный strong ETag. Проверка выполняет только `HEAD` и bounded `GET`: два Range-запроса
читают не более 64 байт, полное содержимое не скачивается.

```bash
python3 ops/media/contract.py \
  --manifest /tmp/quran-media-release.json \
  --json-report /tmp/quran-media-contract-report.json
```

Первый прогон может не указывать `etag`: наблюдаемое значение попадёт в report. Перед release
его следует зафиксировать в manifest и соответствующем `AudioRendition.etag`, затем повторить
прогон, чтобы обнаружить неожиданную замену объекта. SHA-256 проверяет содержимое, а ETag
фиксирует фактический HTTP validator CDN; одно значение не подменяет другое. Gate проверяет
`HEAD 200`, `206`, `416`, `304`, размер/MIME, strong ETag, `Last-Modified`, inline/nosniff и CORS для
каждого клиента и годовой `public, immutable` cache. `--allow-http` предназначен только для
локального эмулятора; production manifest принимает исключительно стабильные HTTPS URL без
credentials/query. Contract report прикладывается к content acceptance record, но не заменяет
лицензионный review и проверку checksum в upload pipeline.

### Immutable upload и фиксация evidence

Production использует переносимые S3-compatible переменные `MEDIA_OBJECT_STORAGE_*` и не имеет
локального `/media/` fallback. Upload выполняется только оператором/release job: uploader сначала
сверяет локальные bytes и SHA-256, затем делает create-only `PutObject` с `If-None-Match: *` и
`ChecksumSHA256`, после чего проверяет объект через `HeadObject`. Повтор совпадающего объекта
безопасен; тот же key с другой metadata никогда не перезаписывается.

Одна подготовленная managed audio rendition загружается по UUID:

```bash
cd services/backend
python manage.py upload_audio_rendition \
  019c0000-0000-7000-8000-000000000001 \
  /data/audio/surah-001-standard.mp3
```

Команда сохраняет `origin_etag`, но ещё не считает публичный CDN проверенным. В manifest для
`ops/media/contract.py` имя каждого аудио asset задаётся строго как
`audio-rendition:<uuid>`. После успешной проверки JSON-report импортируется:

```bash
python manage.py record_audio_media_contract \
  /data/reports/audio-release-media-contract.json
```

Importer принимает только общий `passed=true`, годовой immutable cache, strong ETag, совпадающие
URL/размер/MIME и присутствие всех `MEDIA_CDN_REQUIRED_ORIGINS`. Он сохраняет edge `etag` отдельно
от origin ETag и время evidence. Managed recitation не публикуется, пока хотя бы у одной rendition
нет origin upload или CDN evidence.

Подготовленные 604 страницы Мусхафа загружаются и только затем активируются одной идемпотентной
командой:

```bash
python manage.py publish_mushaf_pages \
  /data/mushaf/madani-hafs/1.0.0/manifest.json \
  --upload --activate
```

В production `--activate` без `--upload` блокируется. Флаг проверяет каждую manifest-запись, но
не заменяет выборочный public-CDN contract report и визуальную/лицензионную приёмку.

## Dependency и container security gate

Backend CI экспортирует только production-зависимости из frozen `uv.lock` вместе с хешами и
проверяет их через закреплённый `pip-audit`. Web CI отдельно запускает полный
`npm audit --audit-level=high`, включая build/test tooling. Production Compose CI после сборки
проверяет Trivy все deployable образы: backend, web, gateway, PostgreSQL и Redis. Любая известная
`HIGH`/`CRITICAL` уязвимость блокирует gate, в том числе пока не имеющая исправления.
Backend и web runtime не содержат package managers; PostgreSQL wrapper flatten'ит финальный
filesystem после замены `gosu` на `su-exec`, поэтому Trivy проверяет реально исполняемые
артефакты, а не удалённые builder/base layers. На момент локальной проверки все пять образов
имели ноль `HIGH`/`CRITICAL` findings без ignore-list.

Локальная проверка backend без изменения lock-файла:

```bash
cd services/backend
uv export \
  --frozen \
  --no-dev \
  --no-emit-project \
  --format requirements-txt \
  --output-file /tmp/quran-backend-audit-requirements.txt
uvx --from pip-audit==2.10.1 pip-audit \
  --requirement /tmp/quran-backend-audit-requirements.txt \
  --require-hashes \
  --disable-pip \
  --strict \
  --progress-spinner off
```

Не добавляйте advisory в ignore-list только ради зелёного релиза. Исключение допустимо после
письменной оценки достижимости, компенсирующих мер, владельца риска и срока удаления; решение
ссылается на конкретный advisory и release commit. Результат gate относится только к
проверенному commit: после изменения lock-файла или Dockerfile проверку нужно пройти заново.

## PostgreSQL backup

Скрипт создаёт custom-format dump, записывает SHA-256, проверяет, что `pg_restore` читает
архив, и только после этого публикует файл атомарным rename. Перед запуском он требует не
менее `BACKUP_MIN_FREE_MB` свободного места (по умолчанию 1024 MiB). Файлы старше
`BACKUP_RETENTION_DAYS` (по умолчанию 14) удаляются только после успешного нового backup.
Custom format выбран в соответствии с официальным
[руководством PostgreSQL 17](https://www.postgresql.org/docs/17/backup-dump.html): он
сжимается и восстанавливается через `pg_restore`.

Хранить backup внутри того же ноутбука или сервера недостаточно. Задайте абсолютный каталог
на отдельном зашифрованном носителе либо синхронизируйте готовые `.dump` и `.sha256` в
закрытое object storage:

```bash
export QURAN_BACKUP_DIR=/absolute/encrypted/quran-backups
docker compose --profile ops run --rm db-backup
```

Команда напечатает путь внутри контейнера, например `/backups/quran_....dump`. Проверка:

```bash
export BACKUP_FILE=/backups/quran_20260823T120000Z.dump
docker compose --profile ops run --rm db-backup-verify
```

Логический dump включает PostgreSQL, но не media/object storage. Изображения Мусхафа и
локальные аудиофайлы должны иметь отдельную versioned-копию с проверкой checksum.

## Restore drill

Checksum и `pg_restore --list` обнаруживают повреждённый/нечитаемый архив, но не заменяют
пробное восстановление. Следующая команда создаёт только БД с префиксом
`quran_restore_check`, восстанавливает архив, проверяет Django schema и удаляет временную БД:

```bash
export BACKUP_FILE=/backups/quran_20260823T120000Z.dump
docker compose --profile ops run --rm db-restore-check
```

Запускайте restore drill после каждого изменения backup-процесса и регулярно по расписанию.

Реальное восстановление отделено профилем `dangerous-restore` и требует точного имени и
подтверждения. Оно удалит БД назначения, если она уже существует:

```bash
export BACKUP_FILE=/backups/quran_20260823T120000Z.dump
export RESTORE_DATABASE_NAME=quran_recovered
export CONFIRM_RESTORE=restore:quran_recovered
docker compose --profile dangerous-restore run --rm db-restore
```

Восстанавливайте только доверенные архивы: PostgreSQL предупреждает, что restore может
выполнить код, содержащийся в dump (см.
[документацию pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html)). Для
аварийного восстановления основной production-БД сначала остановите backend/worker/beat,
сохраните отдельную копию текущего состояния и проверьте выбранный архив через restore
drill.

## Read-only load smoke

Скрипт отправляет только GET-запросы к четырём публичным endpoint'ам. По умолчанию это 120
запросов с concurrency 10, допустимой долей ошибок 1% и p95 не выше 1000 ms:

```bash
python3 ops/load/smoke.py
```

Пример для staging:

```bash
python3 ops/load/smoke.py \
  --base-url https://staging-api.example.org \
  --requests 1000 \
  --concurrency 25 \
  --max-error-rate 0.01 \
  --max-p95-ms 750
```

Это regression-smoke, а не доказательство production capacity. Полноценный capacity-тест
проводится на staging с production-подобными PostgreSQL/Redis и наблюдением CPU, RAM,
connection pools и database latency.

## Staged public-read capacity test

`ops/load/capacity.py` создаёт отдельное keep-alive соединение на виртуального пользователя и
держит заданную concurrency в течение каждой стадии. Встроенный workload смешивает
server-rendered RU/AR web routes, опубликованную суру и публичные Quran/audio API. Он отправляет
только `GET`, не принимает credential headers и ограничивает concurrency, длительность,
количество запросов и размер ответа. Поэтому этот сценарий подходит для согласованного
read-only запуска против staging, но не заменяет отдельные auth/sync/audio-origin сценарии.

Первичная проверка S0 с машиночитаемым evidence report:

```bash
python3 ops/load/capacity.py \
  --base-url https://staging.example.org \
  --stage 10:60 \
  --stage 25:300 \
  --label release-abc1234-s0 \
  --json-report /tmp/quran-capacity-release-abc1234-s0.json
```

Стадия считается неуспешной, если не выдержана заявленная длительность, превышены error-rate,
p95 или p99. Значения по умолчанию: не более 1% ошибок, p95 ≤ 750 ms и p99 ≤ 1500 ms. Перед
запуском согласуйте concurrency и окно со staging owner; для другого профиля явно задайте
пороги CLI и сохраните их в отчёте. Не направляйте harness на production без отдельного
разрешения владельца среды.

JSON-файл становится доказательством ёмкости только вместе с deployment/version label,
production-like topology и временным рядом server-side метрик: CPU/RAM, API RPS и latency,
Gunicorn/DB pool saturation, PostgreSQL query/lock latency, Redis latency/evictions и 5xx.
Локальный или mock-прогон проверяет сам инструмент, но не закрывает S0/S1 capacity gate.

## Capacity profiles и рост

Проект использует профили S0–S3 из
[архитектуры масштабирования](architecture-and-scaling.md). Переход не выполняется только
по DAU: нагрузочный отчёт должен фиксировать workload mix Flutter/web/Telegram Mini App,
requests per active user, sync operations/day, audio minutes/day и peak factor.

Минимальный набор сценариев capacity/soak:

- встроенный public-read workload для web, Quran/audio API уже автоматизирован; дополнительно
  нужны public library reads и отдельные cache-cold/cache-warm прогоны;
- авторизация, token refresh, reading writes и sync push/pull;
- одновременный импорт/retention task без нарушения пользовательского SLO;
- CDN `HEAD`, `Range`, `206`, `416`, CORS/ETag и origin-failure;
- audio startup/buffering для экономной, стандартной и высокой rendition;
- graceful degradation при недоступности Redis, provider API и worker queue.

Отчёт содержит API p95/p99/5xx, DB pool/locks/query latency, Redis latency/evictions,
Celery queue age, CDN byte hit ratio/origin egress и стоимость media на DAU. После теста
фиксируются максимальная проверенная нагрузка, запас, bottleneck, rollback и следующий
конкретный trigger масштабирования.
