# Production operations

Этот runbook покрывает наблюдаемость backend, резервные копии PostgreSQL и ограниченный
нагрузочный smoke-тест. Команды выполняются из корня репозитория.

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

## ISR и content sitemap

Глубокие web-маршруты `/{locale}/quran/{edition}/surah/{number}` и отдельные аяты получают
данные server-to-server через `BACKEND_INTERNAL_URL`. В production Compose это
`http://backend:8000`; публичный browser API по-прежнему идёт через gateway. В ответ не
передаётся `Authorization`: backend publication selectors являются единственной границей,
решающей, какие edition/version доступны поисковому индексу.

Next.js fetch cache обновляет опубликованный Quran-контент не чаще одного раза в час и помечает
запросы тегами edition/surah/ayah. После появления редакционного publish webhook эти теги нужно
инвалидировать on demand; до этого максимальное штатное окно обновления — 60 минут. Персональные
маршруты в этот кэш не входят.

`/sitemaps/quran/sitemap.xml` — индекс, который ссылается на child sitemap с edition и активной
content version в URL. Child sitemap перечисляет только суры и аяты, доступные через public API,
и возвращает 404 для draft, снятой или уже неактивной версии. Оба sitemap указаны в
`robots.txt`. После публикации или отзыва dataset проверьте:

```bash
curl --fail https://example.org/sitemaps/quran/sitemap.xml
curl --fail https://example.org/ru/quran/madani-hafs/surah/1
```

Ошибка upstream не подменяется пустым успешным sitemap: endpoint отвечает 503, чтобы crawler
повторил запрос позднее и не счёл исчезновение контента штатным удалением.

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

## Capacity profiles и рост

Проект использует профили S0–S3 из
[архитектуры масштабирования](architecture-and-scaling.md). Переход не выполняется только
по DAU: нагрузочный отчёт должен фиксировать workload mix Flutter/web/Telegram Mini App,
requests per active user, sync operations/day, audio minutes/day и peak factor.

Минимальный набор сценариев capacity/soak:

- публичные Quran/audio/library reads при cache-cold и cache-warm;
- авторизация, token refresh, reading writes и sync push/pull;
- одновременный импорт/retention task без нарушения пользовательского SLO;
- CDN `HEAD`, `Range`, `206`, `416`, CORS/ETag и origin-failure;
- audio startup/buffering для экономной, стандартной и высокой rendition;
- graceful degradation при недоступности Redis, provider API и worker queue.

Отчёт содержит API p95/p99/5xx, DB pool/locks/query latency, Redis latency/evictions,
Celery queue age, CDN byte hit ratio/origin egress и стоимость media на DAU. После теста
фиксируются максимальная проверенная нагрузка, запас, bottleneck, rollback и следующий
конкретный trigger масштабирования.
