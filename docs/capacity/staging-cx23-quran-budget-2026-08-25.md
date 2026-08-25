# Staging CX23: strict budget Quran public-read capacity evidence

Дата прогона: 25 августа 2026 года. Web artifact: `staging-4ac230d`; backend deployment:
`staging-a5117cb`.

## Почему выполнен повторный прогон

После точечных rollout отдельных сервисов был обнаружен deployment drift: часть контейнеров
сохранила `compose.staging.budget.yaml`, а web/backend/worker/PostgreSQL были пересозданы только
с base + staging Compose. Старый [content-backed отчёт](staging-cx23-quran-content-2026-08-25.md)
остаётся фактом для физического CX23 с более широкими per-container ceilings, но не является
доказательством строгого budget overlay.

Перед повтором проверенный backup
`/backups/quran_staging_20260825T044459Z.dump` был сохранён, затем весь staging без пересборки
образов возвращён к единому budget-профилю. После rollout readiness, Quran shell и опубликованная
сура вернули `200`.

## Фактические runtime limits

| Сервис | CPU limit | Memory limit |
|---|---:|---:|
| web | 0.50 CPU | 448 MiB |
| backend | 0.65 CPU | 512 MiB |
| worker | 0.40 CPU | 384 MiB |
| PostgreSQL | 0.75 CPU | 640 MiB |
| Redis | 0.20 CPU | 128 MiB |
| gateway | 0.15 CPU | 96 MiB |
| TLS proxy | 0.10 CPU | 64 MiB |

Topology: одна реплика каждого application-сервиса на Hetzner CX23 (2 vCPU, 4 GiB RAM).
Dataset: временно активированный только на noindex staging `madani-hafs@1.0.2`, 114 сур,
6 236 аятов и 604 WebP в отдельном `iqro-staging-media`.

## Workload и gate

Использован `ops/load/workloads/web-public-read.json`: server-rendered RU/AR landing, Quran
reader shell, опубликованная сура, Quran/audio catalog API и liveness. Генератор находился вне
VPS, шёл через публичный HTTPS/Caddy/gateway и использовал think time 0: каждый виртуальный
клиент сразу отправлял следующий запрос.

Gate: error rate ≤ 1%, общий p95 ≤ 750 ms, общий p99 ≤ 1 500 ms.

## Результаты

| Непрерывно активные read-клиенты | Длительность | Запросы | RPS | Ошибки | p95 | p99 | Gate |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 5 | 30 s | 857 | 28.36 | 0% | 505 ms | 614 ms | pass |
| 8 | 60 s | 2 144 | 35.70 | 0% | 578 ms | 783 ms | pass |
| 10 | 120 s | 4 612 | 38.41 | 0% | 682 ms | 838 ms | pass |
| 12 | 180 s | 6 949 | 38.56 | 0% | 779 ms | 1 007 ms | **fail p95** |

На ступени 10 тяжёлые SSR endpoints уже были близки к границе: published surah p95 856 ms,
Quran reader shell p95 731 ms. На ступени 12 published surah вырос до 948 ms, reader shell до
815 ms, RU/AR landing — примерно до 842/849 ms. Catalog API оставались в основном ниже 160 ms.

Машинные отчёты:

- [smoke 5/8](staging-cx23-quran-budget-smoke-2026-08-25.json);
- [sustained 10](staging-cx23-quran-budget-sustained-10-2026-08-25.json);
- [boundary 12](staging-cx23-quran-budget-boundary-12-2026-08-25.json).

## Bottleneck и подтверждённая граница

Web почти всё окно держался около CPU ceiling 50%; throughput вышел на плато около 38.5 RPS.
Память web оставалась примерно 80–92 MiB из 448 MiB. PostgreSQL в наблюдавшихся samples был
обычно около нуля и не превышал примерно 6%; Redis также оставался лёгким. Backend имел редкие
CPU spikes при cache fill, но не был постоянной границей этого read-only workload.

Для строгого budget overlay подтверждены **минимум 10 непрерывно активных saturated
read-клиентов**. Ступень 12 не дала ошибок, но нарушила latency SLO и стабильной не считается.
Это не означает только 10 обычных пользователей: профиль без think time намного тяжелее чтения
человеком и не переводится напрямую в DAU.

После теста readiness, Quran shell и опубликованная сура отвечали `200`; в web/backend logs за
окно не найдено 5xx. На host оставалось 2.6 GiB available RAM, swap — 7 MiB, disk — 30%.

Следующий шаг — mixed realistic workload с пользовательскими паузами и guest sync, затем
production-sized S0 soak. Если нужно увеличить именно saturated SSR throughput на том же host,
сначала измеряется вторая web-реплика в пределах общего host CPU budget; постоянная мощность
добавляется только по production telemetry.
