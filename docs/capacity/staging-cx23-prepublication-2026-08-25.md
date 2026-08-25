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
