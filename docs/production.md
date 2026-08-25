# Production-запуск

Если публичной среды ещё нет, сначала пройдите пошаговый [staging runbook](staging.md). Staging
использует тот же production Compose как основу, но отдельные secrets/data, автоматический TLS,
запрет индексации и тестовую почту. Непроверенный staging нельзя заменять прямым первым запуском
production.

`compose.production.yaml` запускает отдельный production-стек: PostgreSQL, Redis,
одноразовую миграцию, Django/Gunicorn, Celery worker/beat, Next.js standalone и Nginx
gateway. Исходный код не монтируется в контейнеры, наружу публикуется только gateway,
а миграция должна успешно завершиться до запуска приложения. Managed media не монтируется
и не раздаётся с application host: публичные URL ведут в отдельный CDN/object storage.

Это односерверный профиль S0/beta и воспроизводимая production-проверка, а не целевая
topology для 50 000–100 000 DAU. Целевая схема сохраняет те же образы, но запускает
stateless API/web/worker replicas за load balancer, подключает managed PostgreSQL/Redis
через connection pool и отдаёт managed media из object storage через CDN. Подробности:
[архитектура расширения и масштабирования](architecture-and-scaling.md).

Домен/TLS, внешний uptime/error monitoring, доставляемый on-call и offsite-хранилище резервных
копий пока намеренно не включены. В репозитории есть opt-in Prometheus/Grafana/Alertmanager
baseline, но его фактический deployment не заменяет эти launch evidence.

Для ограниченного Web MVP существующие staging capacity reports приняты как нижняя измеренная
граница; дополнительные production-sized/load/soak исследования перенесены post-MVP. Это не
разрешает массовое привлечение трафика и не снимает monitoring, offsite backup, security,
content sign-off или rollback smoke. Перед production deploy заполните
[fast-track release plan](release/web-mvp-fast-track-2026-08-25.md) и
[sign-off package](sign-offs/README.md).

## 1. Окружение и секреты

Создайте production-файл из шаблона:

```bash
cp services/backend/.env.production.example services/backend/.env.production
chmod 600 services/backend/.env.production
```

Замените все значения `replace-me`. Для каждого ключа используйте отдельное случайное
значение; секреты development-среды переиспользовать нельзя. Проверьте как минимум:

- `DJANGO_ALLOWED_HOSTS`, CSRF/CORS origins и публичные HTTPS URL;
- `SITE_URL`: один канонический HTTPS origin web-приложения без path/query/hash;
- пароль PostgreSQL и все Django/Quran hash keys;
- пять Redis role URL, включая `WEB_CACHE_REDIS_URL`; для S0 они могут указывать на один
  внутренний Redis endpoint;
- `QURAN_OPERATIONS_TOKEN`;
- независимый `GRAFANA_ADMIN_PASSWORD`, месячный денежный и origin-egress budget; alert webhook
  можно оставить пустым только для локальной проверки dashboard;
- Quran.Foundation credentials, если синхронизация включена;
- `MEDIA_OBJECT_STORAGE_ENDPOINT_URL`, bucket, scoped access/secret key, region/addressing style;
- `MEDIA_CDN_REQUIRED_ORIGINS`: точные origins публичного web, staging и Telegram Mini App,
  которые обязаны присутствовать в CDN contract report;
- `PUBLIC_MEDIA_BASE_URL` и `PUBLIC_AUDIO_BASE_URL`: HTTPS custom-domain CDN, а не API/gateway.

Production settings и `docker compose config` fail closed без этих значений. Credentials должны
иметь доступ только к media bucket; их нельзя передавать web/mobile/Mini App или добавлять в URL.

Файл `.env.production` игнорируется Git. В контейнеры он передаётся через `env_file`,
но не копируется в образы.

## 2. Проверка и запуск

Остановите development-стек либо назначьте production другой `GATEWAY_PORT`, затем:

```bash
make production-config
make production-build
make production-up
make production-ps
```

Observability overlay включается отдельно и не увеличивает стартовый S0 footprint без явного
решения оператора:

```bash
make observability-config
make observability-up
```

Его UI остаются на loopback; порядок настройки budget, alert delivery и provider metrics
описан в [operations runbook](operations.md#versioned-observability-baseline).

Перед release локальный web performance gate можно повторить отдельно; он сам создаёт
standalone production build и запускает детерминированный mock API:

```bash
cd services/web
npm run test:e2e:production
npm run test:lighthouse
```

По умолчанию gateway слушает только `127.0.0.1:3000`. Это безопасная настройка для
reverse proxy на том же сервере. Для публичного запуска TLS-proxy должен передавать
`Host`, `X-Forwarded-For` и `X-Forwarded-Proto: https`. Не выставляйте gateway на
`0.0.0.0` без firewall и настроенного TLS.

Проверки после запуска:

```bash
curl --fail http://127.0.0.1:3000/healthz
curl --fail --header 'X-Forwarded-Proto: https' \
  http://127.0.0.1:3000/api/v1/health/ready
curl --fail http://127.0.0.1:3000/sitemaps/quran/sitemap.xml
curl --fail http://127.0.0.1:3000/ru/quran/madani-hafs/surah/1
curl --fail http://127.0.0.1:3000/sitemaps/audio/sitemap.xml
curl --fail http://127.0.0.1:3000/ru/audio/reciters
python3 ops/load/smoke.py --base-url http://127.0.0.1:3000
```

Для временной проверки только на loopback без TLS можно установить
`DJANGO_SECURE_SSL_REDIRECT=false`. В реальном окружении значение должно оставаться
`true`.

## 3. Что обеспечивает Compose

- backend и web собираются в production targets и работают без hot reload;
- runtime-образы backend/web не содержат package managers (`pip`, `npm`, `yarn`): установка
  зависимостей остаётся только в builder-слоях;
- PostgreSQL собирается как локальный wrapper над закреплённым official image: финальный
  filesystem использует `su-exec` вместо уязвимого Go-based `gosu`, сохраняя контракт
  официального entrypoint;
- контейнеры приложения имеют read-only root filesystem, `no-new-privileges`,
  ограничение процессов, CPU и RAM;
- healthchecks проверяют PostgreSQL, Redis, Django readiness, Next.js и gateway;
- логи Docker ротируются по размеру и количеству файлов;
- только успешная `migrate --noinput` открывает запуск backend/worker/beat;
- Nginx раздаёт только собранный Django `/static/`, проксирует `/api/` в backend и держит
  bounded 24 MiB cache только для allowlisted public catalog JSON; `/media/` локально
  отсутствует, чтобы потеря application-host не уничтожала канонические assets;
- данные PostgreSQL/Redis и собранная статика находятся в именованных volumes.

Лимиты ресурсов задаются в `compose.production.yaml`. Перед размещением на маленьком
сервере сравните их сумму с доступной RAM; Docker применяет лимит каждому сервису
отдельно.

### 3.1. Граница horizontal scale

До добавления второй production application-реплики как S1/multi-host topology необходимо:

- provision'ить production bucket/CDN и загрузить канонические media через готовый immutable
  pipeline; runtime-код и Compose уже не зависят от локального media volume;
- подключить внешний PostgreSQL через PgBouncer-совместимую конфигурацию из раздела ниже;
- убедиться, что backend cache/throttle/Celery и общий web cache используют доступные всем
  репликам Redis endpoints;
- запускать migrations отдельной release-job;
- оставить желаемое число Beat-процессов равным одному; Redis lease блокирует случайный дубль
  и позволяет безопасный failover после TTL;
- включить общий metrics/logging backend и проверку capacity profile.

Количество API, web и worker replicas после этого меняется независимо за внешним
load balancer/orchestrator; single-host gateway остаётся стартовым S0-профилем. PostgreSQL read
replica, отдельные Redis-кластеры и партиционирование добавляются только при измеренной
saturation; они не являются условием небольшого публичного запуска.

Для промежуточного single-host шага gateway использует Docker DNS и каждые пять секунд
обновляет адреса `backend`/`web`, поэтому Compose может безопасно добавить или убрать их
реплики без ручного списка IP и без sticky sessions. Это увеличивает пропускную способность
процессов, но не даёт high availability при потере самого host.

Соберите release images, затем выполните bounded preflight и scale:

```bash
make production-build
make production-scale API_REPLICAS=2 WEB_REPLICAS=2
make production-ps
curl --fail https://example.org/api/v1/health/ready
```

`production-scale` принимает от 1 до 64 реплик каждого типа, автоматически передаёт
`DATABASE_API_REPLICAS` в Compose, валидирует итоговую модель и запускает
`database_connection_budget` в release image до изменения работающей topology. Команда
использует `--no-build`: масштабируется только уже собранный и проверенный release. Worker не
масштабируется этой командой, Beat остаётся в одной реплике.

После scale выполните public-read/sync capacity smoke и проверьте 5xx, p95/p99, PostgreSQL
headroom и Redis latency. Откат числа процессов использует тот же проверяемый путь:

```bash
make production-scale API_REPLICAS=1 WEB_REPLICAS=1
```

Budget staging overlay на CX23 намеренно остаётся с одной web/API-репликой; эту команду нельзя
использовать как способ обойти его CPU/memory ceilings. Multi-replica staging-прогон выполняется
на стандартном или production-sized профиле.

### 3.2. PostgreSQL/PgBouncer connection budget

Стартовый S0 работает напрямую с PostgreSQL (`DATABASE_POOL_MODE=direct`) и объявляет максимум
100 соединений, из которых 20 зарезервированы для администратора, мониторинга и аварийных
операций. Текущая topology оценивается в 19 application clients: API ограничен как
`GUNICORN_WORKERS=2` × `API_MAX_CONCURRENT_REQUESTS_PER_WORKER=5`, Celery —
`CELERY_WORKER_CONCURRENCY=4`, ещё один client выделен Beat и по два — release-job и
operations. Production ASGI всегда требует `DATABASE_CONN_MAX_AGE=0`.

Перед добавлением реплик направьте `DATABASE_HOST`/`DATABASE_PORT` на PgBouncer и установите
`DATABASE_POOL_MODE=transaction`. Настройки автоматически отключат server-side cursors и
автоматические prepared statements. У PgBouncer настройте тот же бюджет:

```ini
[pgbouncer]
pool_mode = transaction
default_pool_size = 40
max_db_connections = 40
max_db_client_connections = 100
```

Значения `DATABASE_PGBOUNCER_SERVER_CONNECTIONS` и
`DATABASE_PGBOUNCER_CLIENT_CONNECTIONS` должны совпадать с фактическими ограничениями pooler.
При каждом scale измените `DATABASE_API_REPLICAS`, `DATABASE_WORKER_REPLICAS`, число Gunicorn
workers и runtime concurrency. Валидатор считает бюджет из этих же исполняемых переменных;
отдельного декларативного лимита, способного разойтись с runtime, нет. До deploy выполните:

```bash
cd services/backend
uv run python manage.py database_connection_budget
```

Команда завершится ошибкой уже при загрузке production settings, если direct clients превышают
доступный бюджет PostgreSQL, PgBouncer server pool выходит за него либо max clients меньше
объявленной topology. После миграций выполняйте PgBouncer `RECONNECT`, если pooler настроен
с поддержкой prepared statements; текущая безопасная конфигурация их не использует.

### 3.3. Redis roles

Production явно требует пять URL: `REDIS_CACHE_URL`, `REDIS_THROTTLE_URL`,
`CELERY_BROKER_URL`, `CELERY_RESULT_BACKEND` и `WEB_CACHE_REDIS_URL`. В S0 они указывают на
один Redis, поэтому дополнительные серверы не нужны. При росте каждый URL можно перевести на
отдельный database, instance или managed endpoint без изменения приложения. Обычный cache,
web cache и security-critical throttling используют разные aliases/key prefixes; backend
readiness проверяет первые два backend aliases, web cache контролируется отдельно.

До deploy проверьте разрешённые endpoints без вывода credentials:

```bash
cd services/backend
uv run python manage.py redis_role_config
```

Cache можно вынести на evictable instance. Для throttle и broker нельзя допускать произвольное
вытеснение ключей: потеря throttle counters ослабляет лимиты, а потеря broker keys удаляет
необработанные задачи. Переключение cache/throttle не требует переноса данных; текущие rate
windows могут начаться заново. Перед сменой broker остановите Beat и producers, дождитесь
пустой старой очереди, переключите workers и producers одной rollout-группой, затем возобновите
постановку задач. Старый result backend удаляется только после истечения нужных результатов.

### 3.4. Stateless API/workers и singleton Beat

Backend и worker используют только PostgreSQL, Redis и object storage как разделяемое
runtime-состояние; их read-only containers имеют лишь временный `/tmp`. Миграции остаются
отдельной release-job. Поэтому API/worker replica не требует копирования media, sessions или
schedule-файлов. Перед изменением числа реплик обновите `DATABASE_API_REPLICAS`,
`DATABASE_WORKER_REPLICAS`, `GUNICORN_WORKERS`, `API_MAX_CONCURRENT_REQUESTS_PER_WORKER` и
`CELERY_WORKER_CONCURRENCY`, затем проверьте DB budget и capacity report.

Worker получает `CELERY_WORKER_PREFETCH_MULTIPLIER=1` по умолчанию: одна реплика не резервирует
пакет длинных задач за собой. Изменять multiplier можно только после queue-specific load test.
Для тяжёлых media/import/export задач перед ростом добавьте отдельную очередь и собственный
concurrency limit; большие файлы и payload не должны проходить через broker.

Beat запускается с `quran_backend.celery_beat.SingletonRedisScheduler`. Расписание находится в
коде/памяти, а лидерство — в ключе `CELERY_BEAT_LOCK_KEY` на `CELERY_BROKER_URL`. Lease живёт
`CELERY_BEAT_LOCK_TTL_SECONDS=60`, продлевается каждые
`CELERY_BEAT_LOCK_RENEW_INTERVAL_SECONDS=20`, а loop просыпается не реже чем раз в
`CELERY_BEAT_MAX_LOOP_INTERVAL_SECONDS=5`. Renew interval обязан быть меньше TTL. Второй Beat
не запускает расписание; потерявший lease прекращает работу, чтобы ограничить риск дублей.
Желаемое число Beat остаётся равным одному: lease — страховка rollout/failover, а не основание
держать лишнюю реплику заранее.

При переносе Celery broker остановите Beat и producers, дождитесь пустой очереди, переключите
workers, затем запустите один Beat с новым broker URL. Старый lease удалять вручную не нужно:
он исчезнет по TTL. Если требуется аварийная проверка, сначала убедитесь, что старый Beat
остановлен, и только затем смотрите TTL ключа; удаление ключа при живом владельце может создать
двух активных scheduler'ов.

### 3.5. Общий Next.js cache

Web использует custom `cacheHandler` для fetch/ISR/route entries и отдельный Next.js handler
для tag coordination. Оба работают через `WEB_CACHE_REDIS_URL`; production Compose передаёт
`WEB_CACHE_REQUIRED=true`, поэтому отсутствующий URL отклоняется при создании handler. Build и
локальная разработка без URL используют только process-local memory fallback.

`WEB_CACHE_KEY_PREFIX=quran-platform:web-cache:v1` изолирует keyspace. Все реплики одного
deployment используют одинаковый prefix; разные environments на общем Redis — разные prefixes.
При несовместимом изменении формата увеличьте суффикс версии вместо
`KEYS`/`SCAN`/массового удаления. Entries имеют hard TTL
`WEB_CACHE_ENTRY_TTL_SECONDS=86400`, tag timestamps —
`WEB_CACHE_TAG_TTL_SECONDS=172800`; startup отклоняет tag TTL короче entry TTL. Размер одной
записи ограничен `WEB_CACHE_MAX_ENTRY_BYTES=8388608`. Fetch content дополнительно сохраняет
свой hourly `revalidate`, поэтому hard TTL не заменяет продуктовую freshness policy.

Redis read error превращается в cache miss, write error не ломает пользовательский ответ.
Ошибка записи invalidation timestamp, напротив, возвращает 5xx из внутреннего revalidation
endpoint, чтобы Celery повторил событие. В S0 web cache указывает на тот же Redis. При росте его
можно первым перенести на отдельный evictable endpoint: эти записи не являются источником
истины. Не переносите вместе с ним throttle или broker без отдельной процедуры из 3.3.

Перед второй web-репликой дополнительно обеспечьте load balancing и одинаковые
`WEB_CACHE_KEY_PREFIX`, `WEB_CONTENT_REVALIDATION_SECRET`, build/image version на всех
инстансах. Gateway public JSON cache уже очищается тем же publication event через защищённый
operations-token adapter и обходит запросы с cookie/`Authorization`. Внешний CDN не должен
кэшировать HTML/RSC до появления отдельного provider purge adapter; media CDN остаётся
независимым immutable-контуром.

## 4. Обновление и откат

Перед обновлением создайте и проверьте backup:

```bash
make production-backup
export BACKUP_FILE=/backups/quran_YYYYMMDDTHHMMSSZ.dump
make production-backup-verify
make production-restore-check
```

Эти команды проверяют локальную копию. Пока offsite bucket отложен, backup всё ещё
нужно вручную переносить на отдельный зашифрованный носитель; backup на том же диске
не защищает от отказа диска или потери сервера.

Затем обновите checkout/образы и повторите `make production-up`. Чтобы откат был
воспроизводимым, в production задавайте неизменяемые `BACKEND_IMAGE`, `WEB_IMAGE` и
`GATEWAY_IMAGE`, а для single-host database — также `POSTGRES_IMAGE` (version tag или
digest). Предыдущие значения сохраняйте в журнале релиза. Миграции должны быть обратно
совместимыми с предыдущей версией приложения.

Остановка без удаления данных:

```bash
make production-down
```

Эта команда сохраняет все volumes. Удаление volumes не входит в штатный runbook.

## 5. Диагностика

```bash
make production-ps
make production-logs
docker compose --env-file services/backend/.env.production \
  -f compose.production.yaml logs --tail=200 backend gateway
```

Если `migrate` завершилась с ошибкой, зависимые сервисы не запустятся. Исправьте причину,
повторно запустите одноразовую миграцию и затем весь стек. Не обходите migration gate.

Операционные health/metrics endpoints, backup/restore и load-smoke подробно описаны в
[operations.md](operations.md).
