# Production-запуск

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

Домен/TLS, внешний мониторинг и offsite-хранилище резервных копий пока намеренно не
включены. До публичного запуска они остаются обязательными инфраструктурными задачами.

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
- четыре Redis role URL; для S0 они могут указывать на один внутренний Redis endpoint;
- `QURAN_OPERATIONS_TOKEN`;
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
- Nginx раздаёт только собранный Django `/static/`, а `/api/` проксирует в backend; `/media/`
  локально отсутствует, чтобы потеря application-host не уничтожала канонические assets;
- данные PostgreSQL/Redis и собранная статика находятся в именованных volumes.

Лимиты ресурсов задаются в `compose.production.yaml`. Перед размещением на маленьком
сервере сравните их сумму с доступной RAM; Docker применяет лимит каждому сервису
отдельно.

### 3.1. Граница horizontal scale

До добавления второй application-реплики необходимо:

- provision'ить production bucket/CDN и загрузить канонические media через готовый immutable
  pipeline; runtime-код и Compose уже не зависят от локального media volume;
- подключить внешний PostgreSQL через PgBouncer-совместимую конфигурацию из раздела ниже;
- убедиться, что cache/throttle/Celery используют внешние Redis endpoints;
- запускать migrations отдельной release-job;
- оставить Beat/scheduler singleton;
- включить общий metrics/logging backend и проверку capacity profile.

Количество API, web и worker replicas после этого меняется независимо. PostgreSQL read
replica, отдельные Redis-кластеры и партиционирование добавляются только при измеренной
saturation; они не являются условием небольшого публичного запуска.

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

Production явно требует четыре URL: `REDIS_CACHE_URL`, `REDIS_THROTTLE_URL`,
`CELERY_BROKER_URL` и `CELERY_RESULT_BACKEND`. В S0 они указывают на один Redis, поэтому
дополнительные серверы не нужны. При росте каждый URL можно перевести на отдельный database,
instance или managed endpoint без изменения приложения. Обычный cache и security-critical
throttling используют разные Django aliases и key prefixes; readiness проверяет оба.

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
