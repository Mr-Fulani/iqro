# Registered-user email auth + sync capacity на budget CX23

Дата прогона: 25 августа 2026 года.

## Что проверено

Каждый виртуальный пользователь выполнял полный новый-account journey:

1. guest bootstrap с отдельной installation credential;
2. `email/start` на уникальный адрес в зарезервированном домене `example.test`;
3. получение шестизначного кода через закрытый Mailpit по локальному SSH-туннелю;
4. `email/verify`, проверка `active` account и новой token family;
5. `/me`, reading-position `sync/push`/`sync/pull`, refresh token и logout.

Коды, email-адреса, installation credentials и tokens не записывались в stdout или JSON.
Harness fail-closed требует точный staging hostname, disposable database, явное разрешение
email challenges, `.test` domain и loopback Mailpit URL. Реальная внешняя почта не использовалась.

Основной workload делал паузу 15 секунд между sync-циклами, refresh — каждые 5 циклов. Gate:
API error rate не более 1%, API p95 не более 750 ms, API p99 не более 1 500 ms и email-delivery
p95 не более 5 секунд.

## Изоляция

Перед прогоном создан и проверен backup
`/backups/quran_staging_20260825T104814Z.dump`, затем восстановлена отдельная база
`quran_registered_capacity_20260825`. В основной `quran_staging` точных run markers осталось 0:

| Run marker | Основная БД | Изолированные devices | Active `.test` accounts |
|---|---:|---:|---:|
| `load.80fe7a37` | 0 | 1 | 1 |
| `load.f3e9cd12` | 0 | 12 | 12 |
| `load.1a28e07f` | 0 | 6 | 6 |

База, Mailpit messages и два остановленных временных backend-контейнера оставлены для аудита и
не удаляются без отдельного решения.

## Результат

| Профиль | API requests | Ошибки | API p95 / p99 | Email p95 | Итог |
|---|---:|---:|---:|---:|:---:|
| diagnostic 1 user, 30 s | 20 | 0% | 377 / 392 ms | 192 ms | PASS |
| 4 users, 120 s | 88 | 0% | 399 / 450 ms | 183 ms | PASS |
| 6 users, 180 s | 186 | 0% | 1 265 / 2 760 ms | 240 ms | FAIL |
| 8 users, 180 s | 248 | 0% | 1 009 / 1 366 ms | 200 ms | FAIL p95 |

Подтверждённый консервативный уровень этого registered-user профиля на текущем CX23 —
**4 одновременно активных пользователя**. Шесть и восемь пользователей завершили все операции
без HTTP-ошибок, но нарушили latency SLO, поэтому стабильной ёмкостью не считаются.

На 6 пользователях p95 `email/start` достиг 2 768 ms, `sync/push` — 1 265 ms. На 8 пользователях
p95 `email/start` был 1 009 ms, `email/verify` — 1 340 ms, `sync/push` — 1 206 ms. Mailpit не
был узким местом: delivery p95 оставался 183–240 ms. В sampled metrics backend кратковременно
достигал 62–65% CPU при лимите контейнера 65%; PostgreSQL достигал примерно 44%, RAM имела
большой запас. Практический bottleneck — CPU-квота единственного backend-процесса на burst-волнах.

## Восстановление

После каждого окна основной backend запускался до `healthy`, затем временный останавливался.
Финальный runtime guard подтвердил budget topology `1 API + 1 web`; readiness, Quran shell и
опубликованная сура вернули HTTP 200. Gateway 5xx за окно — 0. Единственный traceback временного
backend — `CancelledError` на внутренней readiness-проверке при остановке/перезапуске; запросы
harness и публичный gateway 5xx не дали.

## Evidence

- [diagnostic JSON](staging-cx23-registered-diagnostic-2026-08-25.json);
- [4/8 users JSON](staging-cx23-registered-c4-c8-2026-08-25.json);
- [6 users boundary JSON](staging-cx23-registered-c6-2026-08-25.json).

## Что результат не доказывает

- вход в уже существующий аккаунт, transactional guest merge и два одновременных устройства;
- web BFF/cookie browser journey: этот тест проверял прямой API-контракт, общий для native clients;
- длительный soak, concurrent public-read/audio/import и production-sized S0/S1;
- production SMTP provider delivery, потому что staging намеренно использует Mailpit.

Следующий шаг — real licensed multi-reciter audio/QoE и production-sized повтор. Для identity
отдельно остаётся existing-account merge + multi-device cross-client E2E/capacity journey.
