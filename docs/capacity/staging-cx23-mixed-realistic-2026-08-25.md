# Mixed public-read + guest sync capacity на budget CX23

Дата прогона: 25 августа 2026 года.

## Что проверено

На `staging.iqro.forum` одновременно выполнялись два реалистичных контура:

- публичное чтение RU/AR landing, Quran shell, опубликованной суры и Quran/audio API;
- guest bootstrap, проверка сессии, reading-position `sync/push`, `sync/pull`, периодический
  refresh token и logout.

Read-клиент делал паузу 5 секунд между запросами, sync-клиент — 15 секунд между циклами;
refresh выполнялся каждые 5 циклов. Gate: error rate не более 1%, p95 не более 750 ms и p99 не
более 1 500 ms для каждого контура. Это отдельный реалистичный профиль, поэтому его concurrency
нельзя напрямую сравнивать с saturated public-read или тяжёлым isolated sync тестом без пауз.

Среда работала в строгом budget-профиле CX23: один web, один API worker, один Celery worker,
PostgreSQL, Redis и gateway с лимитами из `compose.staging.budget.yaml`. Аудиопоток в этот прогон
не входил: он проверяется отдельным R2/CDN harness.

## Результат

| Профиль | Запросы read / sync | Ошибки | read p95 / p99 | sync p95 / p99 | Итог |
|---|---:|---:|---:|---:|:---:|
| 10 readers + 2 sync, 120 s | 240 / 40 | 0 / 0 | 347 / 672 ms | 275 / 607 ms | PASS |
| 20 readers + 4 sync, 180 s | 710 / 116 | 0 / 0 | 424 / 1 038 ms | 403 / 592 ms | PASS |

Таким образом, подтверждённый нижний предел для этого realistic mixed-профиля — **20 одновременно
активных читателей плюс 4 пользователя синхронизации**. Это не максимум сервера и не оценка DAU:
выше успешной ступени в этом прогоне не поднимались.

Предварительный boundary-прогон также не дал HTTP-ошибок, но показал чувствительность хвостовой
latency к короткому холодному старту и синхронным волнам:

- короткая ступень `20+4` на 60 секунд: read p95 795 ms, sync p95 890 ms — FAIL;
- ступень `50+10` на 180 секунд: read p95 709 ms, но p99 1 810 ms — FAIL; sync p95 643 ms.

После прогрева повтор `20+4` в течение трёх минут прошёл. Поэтому `50+10` нельзя объявлять
стабильной ёмкостью, а `20+4` фиксируется как консервативный проверенный минимум. Во время
успешного окна sampled CPU/RAM не показали постоянного насыщения; наблюдались короткие всплески,
что согласуется с burst-характером workload.

## Изоляция и восстановление

Stateful часть направлялась через временный backend в отдельную восстановленную базу
`quran_mixed_capacity_20260825`. Точный marker финального запуска `load.1509339f` найден 6 раз
в изолированной базе и 0 раз в основной `quran_staging`. База и остановленный временный
контейнер оставлены для аудита и не удаляются без отдельного решения.

После теста основной backend запущен и healthy, временный backend остановлен. Runtime budget
guard подтвердил topology `1 API + 1 web`; readiness, Quran shell и опубликованная сура вернули
HTTP 200. За окно не найдено gateway 5xx. Две backend log-строки `ERROR` относятся к ожидаемому
SIGTERM остановленного перед тестом основного Gunicorn worker, а не к ошибкам запросов.

## Evidence

- [diagnostic smoke JSON](staging-cx23-mixed-smoke-2026-08-25.json);
- [boundary JSON](staging-cx23-mixed-boundary-50-2026-08-25.json);
- [успешный warm mixed JSON](staging-cx23-mixed-warm-2026-08-25.json).

## Что результат не доказывает

- зарегистрированный пользователь с email login/link/merge и несколькими устройствами не
  проверен;
- реальное licensed multi-reciter audio, cold CDN/origin и mobile buffering не входили в тест;
- import/worker contention, длительный soak, production-sized S0/S1 и multi-host HA не проверены;
- число DAU из concurrency не выводится: для него нужны peak factor, длительность сессии,
  requests/user и audio minutes/day.

Следующий capacity-шаг — автоматизировать registered-user journey, затем повторить mixed/soak
на production-sized профиле и отдельно провести real-audio CDN/QoE sign-off.
