# Production operations

Создание первой публичной тестовой среды, DNS/TLS, закрытый Mailpit и подключение отдельного R2
bucket описаны в пошаговом [staging runbook](staging.md). Этот документ начинается с операций
уже развёрнутой среды.

Этот runbook покрывает наблюдаемость backend, резервные копии PostgreSQL, ограниченный
нагрузочный smoke-тест и staged capacity harness. Команды выполняются из корня репозитория.

## Operational health и Prometheus

Liveness и readiness остаются публичными:

- `/api/v1/health/live` проверяет процесс;
- `/api/v1/health/ready` проверяет PostgreSQL, обычный Redis cache и отдельный throttle alias.

Состояние внешней Quran.Foundation намеренно вынесено отдельно: её временный сбой не должен
выключать уже загруженный каталог. Защищённые endpoint'ы:

- `/api/v1/health/operations` — JSON и HTTP 503 при просроченной/ошибочной синхронизации;
- `/api/v1/metrics` — Prometheus text exposition.

Формат генерируется официальным
[Prometheus Python client](https://prometheus.github.io/client_python/). Durable catalog/sync
gauges читаются из PostgreSQL, а HTTP counter/histogram в production используют multiprocess
storage Gunicorn в container-local tmpfs. Метка `route` берётся только из Django route template:
raw URL, query, user ID и request ID в labels не попадают.

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

## Versioned observability baseline

`compose.observability.yaml` — opt-in overlay над S0 production Compose. Он добавляет
Prometheus, Alertmanager, Grafana и exporters PostgreSQL/Redis/Celery; обычный
`make production-up` их не запускает и поэтому не резервирует ресурсы заранее. Образы
закреплены по версиям, Prometheus rules и Grafana dashboard хранятся в
`ops/observability/`, а runtime-конфиг и файлы секретов создаёт одноразовый init-контейнер.
Пароли и webhook URL в сгенерированные несекретные YAML не подставляются.

Перед запуском задайте реальные положительные значения, соответствующие принятому бюджету:

```dotenv
GRAFANA_ADMIN_PASSWORD=<independent-random-password>
OBSERVABILITY_MONTHLY_BUDGET_USD=<monthly-budget>
OBSERVABILITY_MONTHLY_ORIGIN_EGRESS_BUDGET_BYTES=<monthly-origin-egress-budget>
OBSERVABILITY_ALERT_WEBHOOK_URL=https://alerts.example.com/quran
```

Пустой `OBSERVABILITY_ALERT_WEBHOOK_URL` разрешён для локальной проверки dashboard, но в этом
режиме Alertmanager использует receiver без доставки. Публичный release требует HTTPS webhook
или замену receiver на одобренный PagerDuty/Slack/Telegram/on-call канал и успешную доставку
синтетического alert.

Проверка и запуск:

```bash
make observability-config
make observability-up
make observability-logs
```

Grafana, Prometheus и Alertmanager по умолчанию слушают только loopback на портах 3001, 9090
и 9093. Не публикуйте эти UI напрямую: используйте SSH tunnel, VPN или отдельный SSO-proxy.
Retention Prometheus по умолчанию ограничен одновременно 15 днями и 2 GB. У overlay есть
resource limits, но это не reservations; перед включением на маленьком S0 host всё равно
сверьте фактическую свободную RAM. При переходе на managed observability сохраняются те же
metric names, rules и dashboard queries, а локальные stateful сервисы можно не запускать.

### Alert triage

Versioned rules покрывают target availability, API p95/5xx, полноту опубликованного каталога,
PostgreSQL connection budget, Redis memory/evictions, Celery worker/queue/failures и
media/FinOps telemetry. Порог — сигнал расследования, а не команда немедленно покупать
серверы. Для каждого firing alert:

1. зафиксируйте начало, release version и затронутые маршруты/очереди;
2. проверьте target и соседние панели, затем логи по request ID без вывода credentials;
3. остановите rollout либо примените документированный rollback, если нарушен SLO;
4. масштабируйте конкретный насыщенный слой только после подтверждения устойчивого тренда;
5. сохраните ссылку на incident/capacity evidence и скорректируйте baseline после разбора.

`QuranCeleryQueueBacklog > 100`, API p95 750 ms и utilization 70% являются начальными S0
порогами. После первого production-like load/soak прогона их заменяют измеренными SLO, не
ослабляя alert только ради зелёного dashboard.

Если provider не публикует Redis memory limit, срабатывает `QuranRedisMemoryLimitMissing`:
задайте managed plan limit либо явный `maxmemory` ниже container/cgroup limit. Для общего
cache+broker S0 используйте `noeviction`; смена eviction policy или разделение ролей требует
отдельного load/failure теста, потому что broker/result keys нельзя терять как обычный cache.
S0 exporter читает `REDIS_CACHE_URL`, поскольку все role URL указывают на один endpoint. После
физического разделения запускайте отдельный scrape target/exporter на каждый уникальный
cache/throttle/broker/result/web-cache endpoint с bounded `role` label; один зелёный cache
target не доказывает здоровье остальных ролей.

### CDN and FinOps metric contract

Provider adapter или managed monitoring должен нормализовать Cloudflare R2/CDN и billing
telemetry в следующие bounded series:

- `quran_media_cdn_egress_bytes_total{source="edge|origin"}` — counter фактически отданных
  байтов; `source` — единственная обязательная label;
- `quran_media_audio_range_requests_total{status="206|200|416|error"}` — bounded Range outcome;
- `quran_media_audio_start_duration_seconds_bucket` и
  `quran_media_audio_buffering_ratio` — агрегированная QoE без user/device identifiers;
- `quran_finops_month_to_date_cost_usd{category="compute|database|redis|storage|cdn|other"}` —
  gauge month-to-date стоимости по ограниченному набору категорий.

В репозитории ingestion provider credentials намеренно отсутствуют. Пока adapter не подключён,
`QuranMediaCdnTelemetryMissing` и `QuranFinopsTelemetryMissing` должны срабатывать: отсутствие
данных не считается нулевым egress или нулевой стоимостью. Monthly cost и rolling 30-day origin
egress предупреждают на 80% operator-defined budget. Данные CDN/billing сверяются с invoice,
а QoE sampling и retention проходят privacy review до включения в clients.

Перед rollout и после любого разделения Redis roles сохраните redacted topology report:

```bash
cd services/backend
uv run python manage.py redis_role_config \
  > /tmp/quran-redis-roles-release-abc1234.json
```

Команда валидирует только URL/configuration contract. Readiness подтверждает cache/throttle;
Celery broker и result backend дополнительно контролируются по worker heartbeat, queue depth,
oldest message age, task failures и Redis memory/evictions. Ни один отчёт не содержит Redis
username, password или query parameters.

## Celery workers и Beat lease

API и workers не используют локальное постоянное состояние. Масштабируйте их только после
обновления topology-переменных и проверки DB connection budget в разделе capacity ниже.
Worker replicas можно менять независимо по queue depth/oldest message age; значение
`CELERY_WORKER_PREFETCH_MULTIPLIER=1` оставляйте базовым, пока нагрузочный тест конкретной
очереди не докажет пользу другого prefetch.

Beat должен иметь desired replicas = 1. Scheduler не пишет `celerybeat-schedule` на диск и
перед первым tick атомарно получает Redis lease. Второй процесс завершается с сообщением
`Celery Beat singleton lease is already owned by another process`. Если лидер не может
продлить lease или обнаруживает другой token, он завершается fail-closed; supervisor может
перезапустить его после освобождения ключа по TTL.

Проверка lease без вывода Redis credentials:

```bash
docker compose --env-file services/backend/.env.production \
  -f compose.production.yaml exec redis \
  redis-cli TTL quran-platform:celery-beat:lease
```

Если `CELERY_BEAT_LOCK_KEY` переопределён, подставьте его фактическое значение вместо ключа
из примера. Для каждого deployment, использующего общий Redis, namespace ключа должен быть
уникальным.

Для внешнего/managed Redis выполняйте эквивалентную команду через защищённый operator channel,
не помещая URL с паролем в shell history. Значения `-2` (ключ отсутствует) допустимо видеть
между остановкой и failover; `-1` означает ошибочную бессрочную запись и требует расследования.
Алерт обязателен на restart loop Beat, `lease is already owned`, `lease renewal failed` и
`singleton lease was lost`. Ключ нельзя удалять, пока старый процесс жив: token-safe release
защищает штатный shutdown, но ручной `DEL` обходит эту защиту.

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

Gateway отдельно кэширует только публичные `GET`/`HEAD` JSON-маршруты Quran, каталог
чтецов/декламаций, список методов расчёта молитв и зарезервированный префикс `library`.
Запросы с `Authorization` или cookie всегда идут в backend; остальные API, HTML/RSC и
персональные ответы в этот cache zone не попадают. Ответ сохраняется только при явном
`Cache-Control: public`, а ключ различает URI, метод, `Origin` и `Accept`. Локальный cache
ограничен 24 MiB и одним часом неактивности; заголовок `X-Quran-Edge-Cache` показывает
`MISS`, `HIT`, `BYPASS` или результат повторной проверки.

Та же Celery-задача после успешного web revalidation отправляет внутренний `PURGE` в gateway.
Gateway сначала проверяет bearer token через backend operations endpoint и только затем
очищает маленькую public API zone целиком. Это сознательно простой и безопасный первый
контракт: публикации редки, поэтому wildcard purge дешевле и надёжнее списка потенциально
неполных URL. Значение `PUBLIC_API_CACHE_PURGE_URL` внутри Compose по умолчанию равно
`http://gateway:8080/internal/cache/purge-public-api`; operations token не помещается в URL
или логи.

Production web использует общий Redis-backed handler для fetch/ISR/route entries и общий
timestamp каждого invalidated tag. `updateTags` пишет timestamp, `getExpiration` и cache reads
сверяют его без обхода keyspace; `refreshTags` не делает сетевой `SCAN`, потому что локального
tag manifest нет. `WEB_CACHE_TAG_TTL_SECONDS` обязан быть не короче
`WEB_CACHE_ENTRY_TTL_SECONDS`, иначе старая запись могла бы снова стать доступной после
исчезновения tag marker. Одинаковые URL/key prefix обязательны для всех web-реплик.

При недоступности web-cache Redis чтение становится cache miss и страница получает свежие
данные из backend; неуспешная cache write только логируется. Неуспешная запись invalidation
возвращает 5xx, поэтому `core.notify_web_content_change` повторяет событие. Алерты: сообщения
`[web-cache]`, Redis latency/evictions/memory pressure, рост backend public reads и окончательно
failed revalidation task. Для проверки нового deployment выполните `npm run test:cache` сначала
без URL, затем против временного Redis с отдельным `WEB_CACHE_KEY_PREFIX`; production keyspace
тестом не очищайте.

Проверка cache и защищённой очистки после rollout:

```bash
curl -sS -D - -o /dev/null https://example.org/api/v1/prayer/methods
curl -sS -D - -o /dev/null https://example.org/api/v1/prayer/methods
curl -sS -D - -o /dev/null -H 'Authorization: Bearer invalid-test-token' \
  https://example.org/api/v1/prayer/methods
curl -sS -D - -o /dev/null -X PURGE \
  https://example.org/internal/cache/purge-public-api
docker compose --env-file services/backend/.env.production -f compose.production.yaml \
  exec backend python manage.py shell -c \
  "from django.conf import settings; from urllib.request import Request,urlopen; r=Request(settings.PUBLIC_API_CACHE_PURGE_URL,method='PURGE',headers={'Authorization':f'Bearer {settings.QURAN_OPERATIONS_TOKEN}'}); print(urlopen(r,timeout=5).status)"
curl -sS -D - -o /dev/null https://example.org/api/v1/prayer/methods
```

Два первых ответа должны дать `MISS`, затем `HIT`; запрос с заголовком авторизации —
`BYPASS`; operator-команда — успешный HTTP status; первый запрос после неё — снова `MISS`.
Не вставляйте operations token непосредственно в shell history. Неавторизованный внешний
`PURGE` из примера обязан вернуть 401, а обычный метод на purge URL — 405.

Если внешний CDN когда-либо начнёт кэшировать HTML/RSC, тот же publication event нужно
расширить его provider-specific purge adapter. Сейчас gateway намеренно кэширует только
allowlisted public JSON. Immutable media кэшируется отдельно в media CDN и не зависит от ISR
webhook.

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

Пока Quran/audio corpus не активирован из-за незакрытых редакционных или лицензионных gate,
используйте `ops/load/workloads/web-staging-prepublication-read.json`. Он проверяет публичную
web/API оболочку и пустые каталоги, но намеренно не содержит опубликованную суру и не считается
доказательством полной Quran/audio ёмкости:

```bash
python3 ops/load/capacity.py \
  --base-url https://staging.example.org \
  --workload ops/load/workloads/web-staging-prepublication-read.json \
  --stage 5:30 --stage 10:60 \
  --label release-abc1234-prepublication \
  --json-report /tmp/quran-capacity-release-abc1234-prepublication.json
```

Фактический budget-staging пример с границей деградации, пятиминутным soak и server-side
CPU/RAM evidence: [CX23, 25 августа 2026](capacity/staging-cx23-prepublication-2026-08-25.md).
Он не закрывает полный S0/S1 gate по причинам, перечисленным в отчёте.

После временной noindex-активации полного Quran corpus выполнен отдельный
[content-backed CX23 прогон](capacity/staging-cx23-quran-content-2026-08-25.md): 14 saturated
clients выдержали пять минут, 26 510 запросов прошли без ошибок, p95 составил 359 ms. Этот
результат закрывает Quran HTML/API часть, но не audio Range и auth/sync gates.

### Bounded audio CDN/origin capacity test

`ops/load/audio_capacity.py` проверяет самый дорогой контур отдельно от API. Он использует
версионированный media manifest, keep-alive соединение на виртуального пользователя и смесь
`HEAD`, startup `Range` от нулевого байта и seek `Range` из середины объекта. Полные аудиофайлы
не скачиваются. По умолчанию один Range ограничен 256 KiB, concurrency — максимум 200,
стадия — 100 000 запросами и 512 MiB transfer; жёсткий верхний предел явно заданного transfer
cap — 20 GiB. Запускать его против production без отдельного разрешения владельца среды нельзя.

Сначала контракт конкретного релиза должен пройти обычную bounded-проверку:

```bash
python3 ops/media/contract.py \
  --manifest /secure/path/recitation-release.json \
  --json-report /tmp/quran-media-contract-release-abc1234.json
```

Пример warm CDN-прогона. `warm` выполняет по одному startup Range на asset до измеряемых
стадий; warmup записывается в отчёт отдельно:

```bash
python3 ops/load/audio_capacity.py \
  --manifest /secure/path/recitation-release.json \
  --target-role cdn \
  --cache-mode warm \
  --stage 5:60 \
  --stage 20:300 \
  --range-bytes 262144 \
  --max-transfer-bytes-per-stage 536870912 \
  --min-p50-throughput-kbps 640 \
  --label release-abc1234-s0-audio-warm \
  --json-report /tmp/quran-capacity-release-abc1234-s0-audio-warm.json
```

То же можно вызвать через `make ops-audio-capacity AUDIO_CAPACITY_ARGS='...'`. Значение
минимального throughput задаётся из bitrate тестируемой rendition с согласованным QoE-запасом,
а не копируется из примера вслепую. Базовый mix — 10% `HEAD`, 70% startup и 20% seek;
в отчёте фиксируются p95 TTFB, p50 transfer throughput, delivered bytes, ошибки и нормализованные
`hit`/`miss`/`bypass`/`revalidated`/`unknown` cache outcomes.

`--cache-mode cold-start` сам не очищает provider cache: оператор выполняет purge перед одним
коротким прогоном и сохраняет provider evidence. Несколько стадий под этим label уже не являются
полностью cold. Для прямого origin-теста нужен отдельный manifest с origin asset URLs и
`--target-role origin`; флаг только маркирует evidence и намеренно не переписывает hostname.
Origin-прогон требует отдельного окна и меньших лимитов, потому что создаёт реальный egress.

Client bytes и cache outcome нельзя считать точным origin egress: CDN может забрать или
перевалидировать больше данных, чем получил harness. Origin egress, byte hit ratio и стоимость
берутся из provider telemetry за то же окно. TTFB/throughput являются transport proxy для QoE,
но не заменяют browser/mobile telemetry startup и buffering по rendition.

### Stateful auth и reading sync capacity test

`ops/load/sync_capacity.py` воспроизводит отдельного гостя на виртуального пользователя:
guest bootstrap, `/me`, batched reading-position `sync/push`, incremental `sync/pull`, ротацию
refresh token и logout. Installation credentials и access/refresh tokens генерируются CSPRNG,
существуют только в памяти worker и не попадают в stdout или JSON evidence.

Сценарий создаёт постоянные guest/device/session, reading-position и sync-change строки. Поэтому
он fail-closed требует точного hostname, двух явных подтверждений и предназначен только для
staging с disposable database, которую сбрасывают после окна теста:

```bash
python3 ops/load/sync_capacity.py \
  --base-url https://staging.example.org \
  --confirm-target-host staging.example.org \
  --allow-stateful-writes \
  --confirm-disposable-staging-data \
  --stage 5:60 \
  --stage 20:300 \
  --label release-abc1234-s0-sync \
  --json-report /tmp/quran-capacity-release-abc1234-s0-sync.json
```

То же можно вызвать через `make ops-sync-capacity SYNC_CAPACITY_ARGS='...'`. По умолчанию push
содержит одну операцию, think time равен 500 ms, refresh выполняется каждые 20 циклов, один
пользователь ограничен 200 циклами, а стадия — 5 000 sync operations. Жёсткие пределы:
concurrency 100, длительность 900 секунд, batch 20, 500 циклов на пользователя, 20 000 sync
operations и 1 MiB response. Достижение safety cap завершает стадию как failed evidence, а не
как успешную capacity-цифру.

При увеличении `--operations-per-push` учитывайте operation-based hourly/daily throttles:
уменьшайте частоту циклов так, чтобы тест проверял выбранный профиль, а не случайно только
политику rate limit. Каждый запуск маркирует device `app_version=load.<run_tag>` и записывает
верхнюю оценку числа созданных guest users; маркер помогает аудиту, но не заменяет полный reset
disposable staging database. Отчёт сопоставляется с API/DB/Redis metrics и connection budget за
то же окно. На production этот сценарий не запускается.

Перед каждым изменением числа API/worker replicas сначала обновите topology/runtime-переменные
`DATABASE_API_REPLICAS`, `GUNICORN_WORKERS`, `API_MAX_CONCURRENT_REQUESTS_PER_WORKER`,
`DATABASE_WORKER_REPLICAS` и `CELERY_WORKER_CONCURRENCY`. Затем сохраните отчёт рядом с
capacity evidence:

```bash
cd services/backend
uv run python manage.py database_connection_budget \
  > /tmp/quran-database-budget-release-abc1234-s0.json
```

В direct-режиме отчёт обязан оставлять PostgreSQL headroom внутри
`max_connections - reserved_connections`. В transaction-режиме дополнительно сверяйте
`configured_server_connection_limit` и `configured_client_connection_limit` с фактическими
`SHOW DATABASES`/`SHOW CONFIG` PgBouncer. Расхождение означает, что deployment нельзя
масштабировать до исправления конфигурации.

Для single-host Compose API/web scale используйте `make production-scale
API_REPLICAS=N WEB_REPLICAS=M`. Target сам передаёт число API-реплик в database budget,
запрещает нулевые/чрезмерные значения и не пересобирает release image. Полная процедура,
проверка после rollout и rollback описаны в
[production runbook](production.md#31-граница-horizontal-scale).

## Capacity profiles и рост

Проект использует профили S0–S3 из
[архитектуры масштабирования](architecture-and-scaling.md). Переход не выполняется только
по DAU: нагрузочный отчёт должен фиксировать workload mix Flutter/web/Telegram Mini App,
requests per active user, sync operations/day, audio minutes/day и peak factor.

Минимальный набор сценариев capacity/soak:

- встроенный public-read workload для web, Quran/audio API уже автоматизирован; дополнительно
  нужны public library reads и отдельные cache-cold/cache-warm прогоны;
- bounded guest auth, token refresh, reading writes и sync push/pull автоматизированы;
  production-like evidence и сценарий зарегистрированного пользователя остаются;
- одновременный импорт/retention task без нарушения пользовательского SLO;
- bounded CDN/origin `HEAD`, startup/seek `Range`, TTFB, throughput и cache outcomes уже
  автоматизированы; production-like cold/warm/origin evidence, `416` и origin-failure остаются;
- audio startup/buffering для экономной, стандартной и высокой rendition;
- graceful degradation при недоступности Redis, provider API и worker queue.

Отчёт содержит API p95/p99/5xx, DB pool/locks/query latency, Redis latency/evictions,
Celery queue age, CDN byte hit ratio/origin egress и стоимость media на DAU. После теста
фиксируются максимальная проверенная нагрузка, запас, bottleneck, rollback и следующий
конкретный trigger масштабирования.
