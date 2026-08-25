# Staging CX23: stateful guest auth and reading sync capacity evidence

Дата прогона: 25 августа 2026 года. Backend artifact: `staging-a5117cb`. Тест проверял
контур `guest bootstrap → /me → reading sync push/pull → refresh token → logout` на бюджетном
Hetzner CX23 (2 vCPU, 4 GiB RAM).

## Что именно проверено

- из проверенного backup `/backups/quran_staging_20260825T044459Z.dump` создана отдельная
  disposable БД `quran_sync_capacity_20260825`; основная `quran_staging` не переключалась;
- временный backend работал с одной Gunicorn-репликой, `API_MAX_CONCURRENT_REQUESTS_PER_WORKER=16`,
  лимитом 0.65 CPU и 512 MiB RAM — тем же бюджетом API, который задан для CX23 overlay;
- cache/throttling были вынесены в отдельный временный Redis, поэтому test-токены и rate-limit
  counters не попадали в рабочий Redis;
- backend слушал только loopback VPS, а генератор нагрузки находился вне VPS и подключался через
  SSH tunnel; Caddy/gateway/TLS в этот профиль намеренно не входили;
- один виртуальный пользователь создавал отдельного гостя и примерно каждые 500 ms выполнял
  последовательный `sync/push` + `sync/pull`; refresh выполнялся каждые 20 циклов;
- gate: error rate ≤ 1%, общий p95 ≤ 750 ms и p99 ≤ 1 500 ms.

Это намного тяжелее обычного фонового пользователя, который читает между редкими сохранениями
позиции. Результат нельзя напрямую переводить в DAU, число зарегистрированных аккаунтов или
число одновременно открытых вкладок.

## Результаты

| Активные stateful-клиенты | Длительность | Запросы | RPS | Sync operations | Refresh | Ошибки | p95 | p99 | Gate |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|:---:|
| 1 | 15.4 s | 45 | 2.92 | 17 | 8 | 0% | 292 ms | 381 ms | pass |
| 5 | 61.1 s | 656 | 10.73 | 313 | 15 | 0% | 415 ms | 526 ms | pass |
| 8 | 91.6 s | 1 328 | 14.50 | 637 | 30 | 0% | 611 ms | 763 ms | pass |
| 10 | 91.4 s | 1 370 | 15.00 | 655 | 30 | 0% | 833 ms | 978 ms | **fail p95** |

Машинные отчёты:

- [smoke 1](staging-cx23-sync-smoke-2026-08-25.json);
- [sustained 5](staging-cx23-sync-sustained-5-2026-08-25.json);
- [sustained 8](staging-cx23-sync-sustained-8-2026-08-25.json);
- [boundary 10](staging-cx23-sync-boundary-10-2026-08-25.json).

## Bottleneck

На ступени 5 backend использовал до 56% одного CPU при лимите 65%, PostgreSQL — примерно до
44%, память backend — около 111 MiB. На ступени 8 backend достиг 65.9%, то есть фактически
исчерпал свой CPU budget; PostgreSQL доходил примерно до 53%, Redis оставался около 1% CPU.
На ступени 10 backend продолжительно стоял у лимита, PostgreSQL доходил примерно до 61%, а p95
`sync-push` вырос до 918 ms. Память оставалась около 114 MiB, ошибок и timeout не было.

Следовательно, первая граница здесь — CPU одной API-реплики и write-path `sync-push`, а не RAM,
Redis или потоковое аудио. Аудиобайты обслуживаются отдельным R2/CDN-контуром и в этот тест не
входили.

## Подтверждённая граница

Для этой конфигурации честная подтверждённая нижняя граница — **8 одновременно активных
stateful-клиентов тяжёлого sync-профиля**. Ступень 10 функционально обработала все запросы без
ошибок, но не уложилась в принятый p95, поэтому стабильной по SLO не считается.

Это дополняет, а не заменяет отдельные результаты:

- [14 saturated Quran read clients](staging-cx23-quran-content-2026-08-25.md) на HTML/public API;
- [25 synthetic warm-CDN playback clients](staging-r2-synthetic-audio-2026-08-25.md), где
  аудиотрафик не проходил через VPS.

Реальная общая ёмкость приложения определяется смешанным workload: чтение, редкие sync writes,
login, Telegram Mini App/mobile API, фоновые задачи и аудио QoE. Отдельные максимумы нельзя
складывать.

## Изоляция и завершение

После теста аудит по четырём точным `load.<run_tag>` markers показал:

- в основной `quran_staging`: 0 test devices;
- в изолированной БД: 24 test users/devices, 24 reading positions, 1 622 sync changes и
  1 622 idempotency operations.

Временные backend/Redis контейнеры остановлены с exit code 0, но не удалены. Изолированная БД
оставлена для проверки и не удаляется без отдельного решения. Основной staging readiness после
теста отвечал `200`.

## Следующий capacity-шаг

1. Добавить mixed realistic workload с паузами чтения, public Quran reads и редкими sync writes.
2. Добавить registered-user journey и проверить конкуренцию с retention/background jobs.
3. Профилировать `sync-push`; если product telemetry подтвердит нагрузку, увеличить API replicas
   через уже подготовленный stateless scale path, сохраняя PostgreSQL connection budget.
4. Повторить mixed soak на production-sized S0 и из внешних регионов. Только после этого
   фиксировать launch-capacity и связь с DAU.
