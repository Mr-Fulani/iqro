# Staging CX23: Quran content-backed capacity evidence

Дата прогона: 25 августа 2026 года. Web artifact: `staging-4ac230d`; базовый staging
deployment: `a5117cb`.

## Среда и границы результата

- URL: `https://staging.iqro.forum`;
- профиль: Hetzner CX23, 2 vCPU, 4 GiB RAM, 40 GiB disk;
- topology: по одной реплике web/API/worker, PostgreSQL и Redis на том же VPS;
- content: технически активированный только на закрытом от индексации staging
  `madani-hafs@1.0.2`, 114 сур, 6 236 аятов и 604 WebP в `iqro-staging-media`;
- workload: `ops/load/workloads/web-public-read.json`, только публичные `GET`, включая
  server-rendered landing/Quran routes, опубликованную суру и Quran/audio catalog API;
- thresholds: error rate <= 1%, p95 <= 750 ms, p99 <= 1500 ms;
- генератор нагрузки находился вне VPS, think time был равен нулю: каждый виртуальный клиент
  сразу отправлял следующий запрос.

Временная техническая активация `1.0.2` нужна только для noindex staging/load test и не снимает
provenance, legal, religious/editorial или product blocker. Версия не является кандидатом для
production-публикации.

Этот прогон проверяет HTML и JSON API с полным Quran corpus, но не передаёт аудиобайты. В
staging ещё нет принятого аудиорелиза, поэтому R2 audio `Range`, cache-cold origin, startup/seek,
зарегистрированный пользователь и sync mutations остаются отдельными capacity gates.

## Подготовка и smoke

- backup `/backups/quran_staging_20260825T035152Z.dump` прошёл checksum и archive verification;
- все 604 WebP идемпотентно загружены в единственный разрешённый bucket
  `iqro-staging-media`;
- страницы 1, 128 и 604 вернули `200`, `image/webp`, `Accept-Ranges: bytes` и immutable cache
  headers через `media.staging.iqro.forum`;
- `madani-hafs@1.0.2` прошёл publication validator и был активирован на staging;
- `/ru/quran`, `/ru/quran/madani-hafs/surah/1`, Quran page API и readiness вернули `200`;
- исправлены внутренний proxy protocol для SSR и idle timeout общего Redis-backed Next.js
  cache; lint, typecheck, cache tests и production build прошли до rollout.

## Ступенчатый и длительный тест

| Concurrency | Время | Запросы | RPS | Ошибки | p95 | p99 | Gate |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 5 | 30 s | 1 374 | 45.66 | 0% | 214 ms | 367 ms | pass |
| 10 | 60 s | 4 449 | 73.96 | 0% | 298 ms | 434 ms | pass |
| 12 | 180 s | 15 388 | 85.43 | 0% | 327 ms | 445 ms | pass |
| 14 | 300 s | 26 510 | 88.34 | 0% | 359 ms | 535 ms | pass |

На пятиминутной границе 14 самые тяжёлые content-backed endpoints также остались внутри gate:
published surah p95 430 ms/p99 601 ms, Quran shell p95 388 ms/p99 575 ms, RU landing p95
384 ms/p99 534 ms.

Машиночитаемые результаты:

- [smoke 5/10](staging-cx23-quran-smoke-2026-08-25.json);
- [sustained 12](staging-cx23-quran-sustained-12-2026-08-25.json);
- [boundary 14](staging-cx23-quran-boundary-14-2026-08-25.json).

## Server-side evidence

Во время ступеней 10/12/14 web использовал примерно 80–87% CPU и 91–104 MiB RAM. Backend
оставался в пределах 0.3–1.5% CPU и около 180–185 MiB RAM; PostgreSQL не превышал наблюдавшиеся
0.52% CPU и около 42 MiB RAM; Redis достиг около 2.3% CPU и 10 MiB RAM. Свежие журналы во время
длительных ступеней не содержали `5xx` или новых cache warnings.

После теста:

- readiness и content-backed surah route: HTTP `200`;
- host available memory: 2 387 MiB;
- swap: 7 MiB из 2 047 MiB;
- disk: 30%;
- все application containers работали, healthchecked containers были healthy.

## Что можно и нельзя обещать

На этом конкретном CX23 подтверждены **минимум 14 непрерывно активных read-only клиентов** для
Quran HTML/API workload. Это существенно тяжелее 14 обычных открытых сессий, но результат нельзя
напрямую переводить в DAU: для этого нужен профиль реального поведения, think time, доля кэша и
распределение по клиентам.

Полный S0/S1 gate остаётся открытым. Следующий шаг — импортировать один разрешённый staging
аудиорелиз, проверить его manifest/Range и выполнить отдельный bounded audio CDN test. Затем
нужны disposable guest/registered auth+sync test и повторный общий soak на выбранной
production-sized машине.
