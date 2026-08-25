# Итог capacity-тестов staging на CX23

Дата среза: 25 августа 2026 года.

## Короткий ответ

Текущий staging-сервер Hetzner CX23 (`2 vCPU / 4 GiB RAM`) доказанно выдерживает:

- **20 одновременно активных читателей + 4 активно синхронизирующихся пользователя** в
  реалистичном смешанном профиле;
- **10 полностью непрерывных read-клиентов без пауз**, создающих 38,4 запроса в секунду;
- **8 искусственно тяжёлых sync-клиентов**, выполняющих push/pull примерно каждые 500 ms;
- **4 одновременных полных регистрации** с email verification и последующей синхронизацией;
- **25 параллельных аудиоплееров** на отдельном warm R2/CDN-контуре.

Это разные профили, их нельзя складывать. Самая честная стартовая формулировка: **на CX23
проверен soft launch примерно с 20–25 одновременно активными обычными пользователями**.
Сервер, вероятно, обслужит больше спокойных или просто открытых сессий, но это уже не измеренная
гарантия.

Ни один из основных boundary-прогонов не привёл к падению сервера или потере данных. Первой
ухудшалась задержка ответа; ошибки обычно оставались на уровне 0%. Узкое место — CPU-квота web
для SSR и одной API-реплики для auth/sync bursts. RAM, Redis, диск и PostgreSQL connection
budget имеют большой запас.

## Все результаты в одной таблице

| Сценарий | Стабильно пройдено | Где нарушен SLO | Что это означает |
|---|---|---|---|
| Quran HTML/API, без пауз | 10 clients, 38,41 RPS, 0% ошибок, p95 682 ms | 12 clients: p95 779 ms, 0% ошибок | Web CPU вышел на плато; это намного тяжелее поведения человека |
| Реалистичное чтение + guest sync | 20 readers + 4 sync, 0% ошибок, p95 424/403 ms | 50 + 10: 0% ошибок, но read p99 1 810 ms | Консервативная доказанная launch-граница — 20 + 4; 50 + 10 работали, но с редкими медленными ответами |
| Тяжёлый guest auth/sync | 8 clients, 14,5 RPS, 0% ошибок, p95 611 ms | 10 clients: p95 833 ms | Граница одной API CPU-квоты, не лимит количества аккаунтов |
| Новая регистрация + email + sync | 4 clients, 0% ошибок, p95 399 ms | 6/8 clients: 0% ошибок, p95 1 265/1 009 ms | Одновременная волна регистраций становится медленной; обычные уже созданные аккаунты этим тестом не ограничиваются |
| Warm R2/CDN audio | 25 players, 0% ошибок, p95 TTFB 446 ms | 30 players: p95 TTFB 818 ms | Аудиобайты не идут через VPS; это нижняя граница одного тестового CDN-маршрута, не лимит Cloudflare |
| Реальное QF audio | 3 чтеца × сура 1: startup/seek PASS, p95 TTFB 241 ms | 1/3 metadata size drift | Доставка работает; importer исправлен и теперь доверяет фактическому Content-Length |
| Временные 2 API + 2 web на CX23 | 200 API и 100 HTML запросов, 0% ошибок; service failover PASS | Полный corpus mixed capacity не выполнялся | Код и gateway умеют находить реплики и пережить остановку процесса, но потеря одного VPS всё равно остановит весь сервис |

Использованный строгий SLO: error rate не выше 1%, общий p95 не выше 750 ms и p99 не выше
1 500 ms. Поэтому «FAIL» в отчётах чаще означает «ответы стали медленнее нашего строгого
порога», а не «приложение перестало работать».

## Сколько это примерно DAU

DAU — число разных пользователей за сутки, а capacity измеряется одновременной активностью и
RPS. Для предварительной оценки используется формула:

```text
peak active users ≈ DAU × sessions/day × session minutes / 1440 × peak factor
```

Если предположить одну десятиминутную сессию в день и пик в 3 раза выше среднего:

| DAU | Расчётный peak active |
|---:|---:|
| 300 | 6–7 |
| 500 | 10–11 |
| 1 000 | 20–21 |
| 2 000 | 41–42 |

По этой конкретной модели доказанный mixed-профиль соответствует примерно **1 000 DAU**.
Если пользователи проводят в приложении 20 минут, приходят в одно и то же время или активно
переключают страницы, тот же сервер может приблизиться к границе уже на **300–500 DAU**.
Если сессии короткие и трафик равномерный, он может обслужить больше 1 000 DAU.

Поэтому для планирования без production-аналитики принимается диапазон:

- **до 300 DAU** — консервативный beta-режим с большим запасом;
- **300–1 000 DAU** — допустимый soft launch на CX23 при включённом мониторинге;
- **выше 1 000 DAU** — не обещать на CX23 заранее; решение принимается по реальным peak
  active, RPS, CPU и p95;
- **5 000+ DAU** — планировать уже на более мощном production-профиле и повторять короткий
  mixed capacity test;
- **100 000 DAU** — архитектурная цель горизонтального масштабирования, а не мощность одного
  CX23.

Это инженерная оценка, а не измеренный DAU-рекорд. После запуска она заменяется фактическими
session duration, peak factor, requests/session и audio minutes/day.

## Какой production-сервер закладывать

Для небольшого закрытого beta текущего CX23 достаточно. Для публичного Web MVP разумный
стартовый запас — **4 vCPU / 8 GiB RAM**:

- две web- и две API-реплики можно разместить с реальными CPU budgets;
- CPU-bursts регистрации/синхронизации и SSR получают запас;
- PostgreSQL/Redis пока могут остаться на той же машине ради бюджета;
- audio продолжает идти напрямую через QF или object storage/CDN, а не через VPS.

Это рекомендация, а не измеренный результат для 4 vCPU: production-профиль проверяется коротким
smoke/mixed тестом после deployment. Покупать инфраструктуру под 100 000 DAU заранее не нужно.

## Когда увеличивать мощность

Апгрейд или добавление реплик выполняется, если хотя бы один сигнал держится 10–15 минут:

- host/application CPU выше 70–80%;
- p95 публичного API/HTML выше 750 ms;
- 5xx выше 1%;
- устойчивый внешний трафик выше 15–20 application RPS;
- одновременно активно больше 20–25 пользователей и latency растёт;
- PostgreSQL connections используют более 70% бюджета;
- очередь Celery растёт и не возвращается к нулю;
- disk выше 80% или backup не проходит проверку.

Первый дешёвый шаг: увеличить сервер до 4 vCPU / 8 GiB и запустить `2 web + 2 API`. Следующий:
вынести PostgreSQL/Redis, поставить внешний load balancer и добавить второй application host.
Application containers уже stateless, web cache общий, Redis roles разделены, DB connection
budget проверяется автоматически, а media не зависит от локального диска VPS.

## Что тесты реально дали проекту

Помимо цифр, во время прогонов найдены и исправлены реальные проблемы:

- устранён deployment drift, из-за которого разные контейнеры имели разные resource limits;
- browser/API concurrency limit увеличен с непрактичных 4 до проверенных 16;
- исправлены SSR proxy protocol и idle timeout общего Redis-backed Next.js cache;
- проверены gateway cache `MISS/HIT/BYPASS/PURGE` и защищённая invalidation;
- подтверждены backup → disposable restore → test → возврат staging без загрязнения основной БД;
- найдена CPU-граница web SSR и API `sync-push`, вместо прежних предположений о PostgreSQL;
- доказано, что аудиотрафик не идёт через Hetzner VPS;
- исправлен R2 Range contract harness;
- найдено расхождение QF metadata/origin file size, importer теперь проверяет реальный размер;
- проверены discovery, равномерное распределение и scale-down для `2 API + 2 web`.

## Что готово и чего ещё нет

### Готово

- бюджетный staging CX23, домен, TLS, firewall и noindex;
- полный Quran corpus на закрытом staging для технической проверки;
- RU/EN/AR/TR, AR/RTL, canonical, hreflang, robots, sitemap, 404 и private noindex;
- production build, browser E2E, Lighthouse/SEO regression;
- Quran public-read, guest sync, registration, mixed и CDN audio capacity evidence;
- backup/restore drill и изоляция тестовых БД;
- R2 custom media domain, Range/CORS/cache contract;
- stateless web/API/worker, общий Redis cache и готовый путь к репликам;
- bounded проверка реальной доставки трёх QF audio assets;
- fast-track release/sign-off package.

### Не готово или намеренно перенесено

- `madani-hafs@1.0.2` нельзя публиковать: page artwork имеет незакрытый provenance;
- нет нового принятого immutable Quran dataset;
- нет license/religious/product sign-off;
- QF audio catalog всех 114 сур ещё не прошёл integrity validation и не опубликован;
- нет production SMTP test, existing-account/multi-device journey;
- нет внешнего uptime/error alert с проверенной доставкой;
- нет offsite PostgreSQL backup с production restore evidence;
- production-сервер и production deployment ещё не созданы;
- Search Console/Core Web Vitals проверяются только после публичного deployment;
- full real-audio soak, production-sized/multi-region и S1/HA capacity намеренно перенесены
  после Web MVP.

## Итоговый release verdict

**По производительности проект готов к закрытой beta и осторожному Web MVP soft launch.**
Текущие блокеры публичного production — происхождение/приёмка Quran content, внешние sign-off,
monitoring, offsite backup и сам production deployment, а не отсутствие ещё одного
нагрузочного теста.

Исходные доказательства:

- [strict Quran read](staging-cx23-quran-budget-2026-08-25.md);
- [realistic mixed](staging-cx23-mixed-realistic-2026-08-25.md);
- [guest auth/sync](staging-cx23-stateful-sync-2026-08-25.md);
- [registered account](staging-cx23-registered-user-2026-08-25.md);
- [synthetic R2 audio](staging-r2-synthetic-audio-2026-08-25.md);
- [real Quran.Foundation audio](staging-qf-real-audio-2026-08-25.md);
- [pre-publication and replica drill](staging-cx23-prepublication-2026-08-25.md).
