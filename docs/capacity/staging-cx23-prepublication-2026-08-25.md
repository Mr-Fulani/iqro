# Staging CX23: pre-publication capacity evidence

Дата прогона: 25 августа 2026 года. Целевой commit: `1067548df59fdd344043d6861dd5605275e55bc4`.

## Среда и границы результата

- URL: `https://staging.iqro.forum`;
- профиль: Hetzner CX23, 2 vCPU, 4 GiB RAM, 40 GiB disk;
- topology: budget staging overlay, по одной реплике web/API/worker, PostgreSQL и Redis на том
  же VPS;
- workload: `ops/load/workloads/web-staging-prepublication-read.json`, только публичные `GET`;
- thresholds: error rate <= 1%, p95 <= 750 ms, p99 <= 1500 ms;
- генератор нагрузки находился вне VPS, think time был равен нулю: каждый виртуальный
  пользователь непрерывно держал один запрос в работе.

Результат относится только к web/API оболочке, пустым Quran/audio каталогам и prayer page.
Он не включает опубликованный Quran corpus, зарегистрированного пользователя, sync mutations,
аудио `Range` из R2 и cache-cold CDN/origin. Поэтому это нижняя граница текущего бюджетного
staging, а не S0/S1 или DAU-гарантия production.

## Browser/HTTP smoke

- RU, EN и TR landing/Quran/audio/prayer/login и локализованная 404 отрендерились без
  `HTTP 503`; EN/TR отдали `lang=en|tr`, `dir=ltr` и locale-specific canonical;
- AR Quran отдал `lang=ar`, `dir=rtl` и правильный canonical;
- EN/TR login отдали `noindex, nofollow`, неизвестные маршруты — HTTP 404 и `noindex`;
- `robots.txt` и `sitemap.xml` вернули HTTP 200; sitemap содержит EN/TR locale/hreflang links,
  а staging закрыт `Disallow: /`;
- readiness после всех прогонов: database/cache/throttling `true`.

Обычный cold-load reader раньше превышал лимит из четырёх API-запросов. В budget overlay лимит
поднят до 16. Расчётный database budget после изменения: 25 client connections при 80 доступных,
headroom 55.

## Ступенчатый тест

| Concurrency | Время | Запросы | RPS | Ошибки | p95 | p99 | Gate |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 5 | 30 s | 913 | 30.02 | 0% | 365 ms | 541 ms | pass |
| 10 | 30 s | 1 170 | 38.77 | 0% | 618 ms | 726 ms | pass |
| 20 | 40 s | 1 878 | 46.77 | 1.86% | 899 ms | 1 089 ms | fail |
| 40 | 40 s | 1 889 | 46.12 | 4.34% | 1 668 ms | 2 094 ms | fail |

На 20/40 concurrency backend достиг bounded Uvicorn limit и записал `Exceeded concurrency
limit`; это защитные 503, а не PostgreSQL/RAM failure.

Уточняющий прогон показал:

| Concurrency | Время | Запросы | RPS | Ошибки | p95 | p99 | Gate |
|---:|---:|---:|---:|---:|---:|---:|:---:|
| 12 | 35 s | 1 228 | 34.92 | 0% | 746 ms | 1 057 ms | pass |
| 14 | 35 s | 1 400 | 39.41 | 0% | 745 ms | 981 ms | pass |
| 16 | 35 s | 1 591 | 45.31 | 0.38% | 814 ms | 1 031 ms | fail |

## Пятиминутный soak на доказанной границе

Concurrency 14 выдержана полные 300 секунд: 12 853 запроса, 42.83 RPS, error rate 0.02%
(3 запроса), p95 723 ms, p99 1 009 ms. Общий gate прошёл. Отдельные тяжёлые HTML endpoints
имели p95 до 813 ms, поэтому следующий цикл оптимизации должен включать edge/data cache и
полный content-backed workload.

Пиковый sample server-side метрик во время soak:

- суммарный CPU контейнеров: 170.85% из доступных 200%;
- backend CPU: 65.70%, web CPU: 51.79%, PostgreSQL CPU: 59.35%;
- суммарная память контейнеров: около 486 MiB;
- после теста host available memory: 2 709 MiB, swap usage: 0;
- disk usage: 26%.

Пики отдельных контейнеров не обязательно пришлись на одну секунду. CPU и bounded API
concurrency — текущие ограничения; RAM, disk и database connection budget имеют запас.

## Что можно и нельзя обещать

На этом конкретном CX23 доказаны 14 непрерывно активных виртуальных пользователей в
pre-publication read workload. Это намного жёстче обычной открытой browser session, потому что
между запросами нет пауз, но переводить результат напрямую в DAU или обычных одновременных
посетителей нельзя без production traffic model.

Полный capacity gate остаётся открытым. Следующий обязательный прогон выполняется после
контентного sign-off и включает опубликованную суру, R2 audio manifest/Range, guest/registered
sync, cache-cold/warm фазы и длительный soak на выбранном production-профиле. Горизонтальное
масштабирование API/web проверяется до увеличения рекламируемой ёмкости.

## Post-rollout проверка gateway public API cache

На commit `45faa2e7cab57c439183a4020b7a5abaf76f1232` после проверенного backup выполнена отдельная
проверка bounded gateway cache. Это regression/smoke evidence, а не замена ступенчатого
capacity-теста выше.

Проверенный контракт через реальный `https://staging.iqro.forum`:

| Сценарий | Результат |
|---|---|
| Первый/повторный public catalog GET | `200 MISS` → `200 HIT` |
| Quran editions, reciters, recitations | для каждого `MISS` → `HIT` |
| GET с `Authorization` | `200 BYPASS` |
| GET с cookie | `200 BYPASS` |
| Health endpoint | `200`, без edge-cache header |
| Внешний `PURGE` без operations token | `401` |
| Обычный GET на purge endpoint | `405` |
| Внутренний авторизованный `PURGE` | `200`, следующий catalog GET снова `MISS` |

После этого `ops/load/smoke.py` выполнил 200 запросов с concurrency 10 и одним warmup round:

| Endpoint | Запросы | Ошибки | p50 | p95 | max |
|---|---:|---:|---:|---:|---:|
| health/live | 50 | 0 | 185.7 ms | 296.3 ms | 419.0 ms |
| quran/editions | 50 | 0 | 106.0 ms | 219.3 ms | 282.0 ms |
| reciters | 50 | 0 | 109.1 ms | 275.7 ms | 284.5 ms |
| recitations | 50 | 0 | 115.4 ms | 215.8 ms | 290.3 ms |
| **Итого** | **200** | **0** | — | **283.5 ms** | — |

Smoke gate с лимитом p95 1000 ms прошёл. После прогона gateway cache занимал 24 KiB при
жёстком лимите 24 MiB; gateway использовал около 4.6 MiB RAM. Все контейнеры были healthy,
readiness и RU/EN web вернули HTTP 200, в последних gateway/worker logs ошибок не было.

Каталоги staging пока пусты, поэтому эти числа доказывают корректность `MISS/HIT/BYPASS/PURGE`
и отсутствие очевидной регрессии на CX23, но не производительность с полным Quran corpus,
реальными audio manifests/Range, зарегистрированными пользователями или CDN cache-cold origin.
