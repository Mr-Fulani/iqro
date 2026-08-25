# Web MVP fast-track release plan

Дата решения: 25 августа 2026 года.

Цель: выпустить качественный публичный Web MVP в сжатый срок, используя уже собранные
технические доказательства. Полный цикл нагрузочных исследований не является блокером этого
ограниченного запуска и переносится в post-MVP. Решение не отменяет проверки точности Корана,
прав на контент, безопасности, резервного копирования и отката.

## Граница первого релиза

В первый публичный релиз входят:

- web-клиент с locale-prefixed RU/EN/AR/TR URL, SSR, canonical/hreflang, sitemap и robots;
- гостевой режим и уже проверенные пользовательские сценарии;
- только тот Quran dataset, для которого заполнен отдельный acceptance record;
- только те чтецы, для которых заполнен отдельный audio sign-off record;
- streaming внутри официальных клиентов проекта без offline download и без копирования
  Quran.Foundation audio в R2;
- стартовая односерверная S0-топология с медиа вне application host.

В первый публичный релиз не входят:

- Flutter и Telegram Mini App как готовые клиенты;
- offline audio и redistribution packages;
- непроверенные page artwork из `madani-hafs@1.0.2`;
- автоматическая публикация новых чтецов без отдельной приёмки;
- обещание ёмкости на 100 000 DAU.

API, auth/sync protocol, stateless application containers, object storage boundary и
provider-neutral media model при этом сохраняют возможность добавить mobile, Telegram Mini
App, dua, learning cards и новые функциональные домены без переписывания ядра.

## Что уже достаточно проверено для ограниченного запуска

- staging-домен и TLS работают, staging закрыт от индексации;
- RU/EN/AR/TR, RTL, canonical, login/noindex, 404, robots и sitemap проверены;
- production build, lint, typecheck, browser E2E и Lighthouse gates реализованы;
- backup/restore drill staging выполнен;
- CX23 подтвердил строгий Quran read workload на 10 постоянно активных saturated clients;
- realistic mixed workload подтвердил `20 readers + 4 sync users` без ошибок;
- synthetic R2 подтвердил Range/CDN contract и 25 warm playback clients;
- bounded real-audio probe подтвердил доставку трёх QF assets и привёл к исправлению
  недоверенных `file_size` metadata.

Эти цифры являются нижней доказанной технической границей тестового профиля, а не прогнозом
DAU. Обычный пользователь не отправляет запросы непрерывно, поэтому переводить concurrency в
DAU без production-телеметрии нельзя.

## Блокеры публичного Web MVP

| Gate | Ответственный | Evidence | Статус |
|---|---|---|---|
| Release scope заморожен | Product owner | Этот документ | Ожидается |
| Quran dataset provenance и integrity | Engineering + external reviewers | Новый immutable acceptance record | Ожидается |
| Quran.Foundation audio use | Product owner/QF | Письменный ответ или сохранённые применимые Terms | Ожидается |
| Религиозно-редакционная проверка | Квалифицированный reviewer | Заполненный review record | Ожидается |
| Privacy/Terms/operator contacts | Product owner | Публичные RU/EN/AR/TR страницы | Ожидается финальная сверка |
| Release CI/security | Engineering | Зелёный CI на release commit | Ожидается |
| External uptime/error alert | Engineering + product owner | Доставленное тестовое уведомление | Ожидается |
| Offsite PostgreSQL backup | Engineering + product owner | Backup, checksum и restore evidence | Ожидается |
| Production deploy и rollback smoke | Engineering | Release journal | Ожидается |
| Product sign-off | Product owner | Подписанная секция ниже | Ожидается |

Незаполненный gate не трактуется как молчаливое разрешение.

## Осознанно перенесено после Web MVP

- полный 114-surah real-audio performance/soak test;
- multi-region и production-sized capacity test;
- provider cache-cold/origin stress test;
- existing-account merge под длительной нагрузкой;
- mobile/Telegram QoE и background playback;
- S1 multi-host/load-balancer capacity proof.

Эти работы выполняются по production-метрикам перед расширением трафика, подключением offline
audio или переходом к S1. Нагрузочный тест чужого Quran.Foundation CDN не проводится.

## Компенсирующие меры первого запуска

- soft launch без платного привлечения большого трафика;
- только одна заранее принятая content/audio version, без auto-publish;
- audio streaming можно выключить независимо от чтения Корана;
- rate limits, connection budget и resource limits остаются включёнными;
- uptime/error/CPU/RAM/disk/5xx и расходы на медиа получают alerts;
- ежедневный offsite backup PostgreSQL с проверкой checksum;
- rollback на предыдущие application images и content pointer;
- пересмотр capacity после первых 7 дней и после первых 1 000 DAU.

Стоп-условия: устойчивые 5xx выше 1%, p95 API выше 1 500 ms в течение 15 минут, заполнение
диска выше 80%, недоступный backup, обнаруженная ошибка Quran content или требование
правообладателя. При content/license incident соответствующий dataset/recitation снимается с
публикации, cache очищается, а чтение переводится на последнюю принятую версию.

## Product release decision

Заполняется владельцем только после закрытия таблицы блокеров:

- Release commit/image tags: `________________________________`
- Public origin: `________________________________`
- Quran content version: `________________________________`
- Audio release versions: `________________________________` или `audio disabled`
- Решение: `APPROVED / REJECTED`
- Имя и роль: `________________________________`
- Дата и timezone: `________________________________`
- Комментарий/ticket: `________________________________`

Формулировка решения:

> Я подтверждаю выпуск указанной версии Web MVP в зафиксированном ограниченном scope. Мне
> известны перенесённые post-MVP проверки, стоп-условия и процедура отката.
