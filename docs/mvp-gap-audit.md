# P0/MVP gap audit

Дата аудита: 23 августа 2026 года  
Аудируемый baseline: `efc0f17` (`feat: add hardened production compose stack`)  
Источник требований: [утверждённое ТЗ](../thoughts/shared/specs/2026-08-09-quran-platform-backend.md)

## Правила оценки

- ✅ **Готово** — требование реализовано и подтверждается кодом, данными и тестом/проверкой.
- 🟡 **Частично** — полезный вертикальный срез есть, но полное P0-требование или один из
  обязательных клиентов не закрыт.
- ❌ **Нет** — домен или обязательный клиентский сценарий отсутствует.
- ⏸ **Внешний gate** — реализация зависит от лицензии, редакционного или launch sign-off.

Статус оценивается по полному многоклиентскому MVP (Flutter, web и Telegram Mini App),
поэтому работоспособный web-preview сам по себе не закрывает Flutter/offline критерии.
Зафиксированное ТЗ не изменяется задним числом: этот документ является status overlay.

## Краткий итог

| Срез | Готово | Частично | Нет | Внешний gate |
|---|---:|---:|---:|---:|
| 18 P0-групп | 1 | 13 | 4 | 0 |
| 36 критериев приёмки | 8 | 14 | 12 | 2 |

Сильная часть текущего baseline — канонический Quran dataset, публичное Quran/audio API,
гостевая сессия, позиции/закладки, надёжная offline-синхронизация серверного состояния,
prayer engine/profile, local-only reminder rules, feedback и production runtime. Основной
незакрытый объём находится в зарегистрированном аккаунте/guest merge, Flutter, offline
packages, расширенном плеере, локальном планировщике уведомлений, локализации и отсутствующих
контентных/коммерческих доменах.

## Доказательная база

- Dataset `madani-hafs@1.0.1`: 114 сур, 6 236 аятов, 604 страницы, 30 джузов,
  12 346 региональных сегментов; source commits и SHA-256 закреплены в
  [source lock](../services/backend/docs/quran-sources.lock.json) и dataset manifest.
- В media-каталоге присутствуют 604 versioned WebP-страницы и asset manifest с SHA-256.
- Backend предоставляет Quran, audio, guest auth, reading/sync, prayer/profile,
  reminders, feedback, health/metrics и OpenAPI endpoints.
- В backend test suite находится 311 тестовых функций (parameterization расширяет число
  фактических cases); сохранённый coverage artifact показывает 88,32% line coverage и
  70,96% branch coverage.
- Web имеет только два Playwright-сценария: первый запуск каталога аудио и выбор
  многосегментного аята 6:2 с запуском аудио.
- Production Compose ранее прошёл isolated runtime smoke: migrations/static gates,
  frontend/API/media, HTTPS proxy path, resource limits и 120/120 read-only запросов.
- Live inventory development-БД во время этого аудита повторно не читался: Docker Desktop
  был вручную поставлен на паузу. Статусы данных основаны на versioned manifests и коде,
  а не на изменяемом локальном состоянии.

## Матрица P0

| # | Требование P0 | Статус | Реализовано | Для полного P0 не хватает |
|---:|---|:---:|---|---|
| 1 | Гостевой режим и единый аккаунт | 🟡 | Guest bootstrap, devices, access/refresh rotation, logout, `AuthIdentity` model | Verified login/linking, регистрация обычного пользователя, guest-to-account merge, re-auth flows |
| 2 | RU/EN/AR и RTL | 🟡 | Многоязычные имена контента, locale constraints, арабский RTL-текст | Web зафиксирован на `lang=ru`; нет i18n routing/catalog, language switch и полного RTL UI |
| 3 | Мадинский Мусхаф Хафс, 604 страницы | ✅ | Versioned dataset, 114/6 236/604/30, source lock, checksums, 604 WebP assets | До публичного релиза всё ещё нужен религиозно-редакционный и лицензионный sign-off |
| 4 | Навигация по page/surah/ayah/juz/hizb/rub | 🟡 | API page/surah/ayah/juz; web выбирает суру и страницу | Нет моделей/API/UI для hizb и rub‘ al-hizb; в web нет полноценного перехода по juz и точному аяту |
| 5 | Интерактивные области аятов | 🟡 | 12 346 polygon segments, 6 236 ayah coverage, группировка сегментов, E2E для 6:2 | Нет viewport/device regression matrix и приёмки всех сложных страниц; ранее наблюдались неверные выделения |
| 6 | Позиции, закладки, история, цели, серии | 🟡 | Position, bookmarks, revisions, tombstones и sync | Нет reading sessions/history, goals и streaks |
| 7 | Несколько чтецов, streaming и offline audio | 🟡 | QF catalog/sync, immutable recitations, 114 surah tracks, ayah timings, streaming | Не доказаны три полностью лицензированных релиза; нет управляемой offline-установки и redistribution pipeline |
| 8 | Repeat/range/pause/speed/sleep timer | 🟡 | Воспроизведение суры и отдельного аята, native browser controls | Нет repeat/range mode, учебных пауз, скорости 0,5–2,0× и sleep timer |
| 9 | Flutter background playback/media controls | ❌ | — | Flutter workspace и platform audio service отсутствуют |
| 10 | Offline packages и восстановление sync | 🟡 | Idempotent push/pull, conflicts, cursors, full resync, tombstones для reading/reminders | Нет package domain/manifest API, resumable installer, durable client outbox и полноценного offline web/Flutter клиента |
| 11 | Заглушки переводов и тафсиров | ❌ | — | Нет `translations`/`tafsir` models, API и placeholder UI |
| 12 | Намаз, методы, мазхаб, поправки | 🟡 | Versioned methods/releases, engine, golden cases, privacy-safe profile, high-latitude/polar rules, web fallback | Web не управляет полным prayer profile; Flutter local parity и региональный content review отсутствуют |
| 13 | Локальные уведомления и напоминания | 🟡 | Local-only prayer/reading/review rules, revisions, retention, sync | Нет клиентского scheduler, permission/diagnostics flow и перепланирования после timezone/location changes |
| 14 | Управляемая реклама | ❌ | Только feedback context/category для жалобы на рекламу | Нет campaign/creative/placement/frequency cap/moderation/kill-switch домена |
| 15 | Внешние donation links | ❌ | Только feedback category для жалобы на ссылку | Нет allowlist, safe redirect, admin workflow и клиентского placement |
| 16 | Feedback и editorial workflow | 🟡 | Tickets, immutable context/messages/audit, SLA routing, operator admin | Нет безопасных attachments, user notifications и editorial change request/review/approval workflow |
| 17 | Django Admin и специальные admin API | 🟡 | 30 model registrations для реализованных доменов | Нет полной role matrix, MFA/break-glass safeguards и административных разделов отсутствующих доменов |
| 18 | Observability, backup, audit, CI/CD | 🟡 | Health/readiness/metrics, structured privacy logging, CI, production Compose, local backup/verify/restore drill, load-smoke | Нет capacity/soak proof, централизованных dashboard/alerts, backend/container security gate и offsite backup; monitoring и bucket отложены |

## Критерии приёмки

### Коран

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Утверждённое опубликованное издание 114/30/604 | 🟡 | Технический артефакт полный; нет зафиксированного религиозного и лицензионного acceptance record |
| Assets и канонические данные прошли integrity pipeline | ✅ | Source lock, per-file/asset SHA-256, builder/import/publication tests |
| Переход к любой суре, аяту, джузу и странице | 🟡 | API покрывает все четыре адресации, web UI — не все |
| Стабильный выбор области на поддерживаемых размерах | 🟡 | Есть structural checks и один E2E case, но нет viewport matrix/full acceptance |
| Позиция восстанавливается локально и на другом устройстве | 🟡 | Backend cross-device revisions/sync реализованы; registered cross-client flow отсутствует |

### Аудио

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Минимум три полностью лицензированных чтеца | ⏸ | API не ограничивает количество, но production rights/sign-off не зафиксирован в репозитории |
| Stream/offline/repeat/range/speed/pause/timer | 🟡 | Streaming, surah/ayah playback и pause есть; остальные режимы отсутствуют |
| Flutter background/lock-screen controls | ❌ | Flutter отсутствует |
| Корректное восстановление после interruption | ❌ | Нет platform player/state machine и device tests |
| Повреждённый файл не устанавливается | ❌ | Checksums присутствуют в контракте, но client package installer отсутствует |

### Намаз и напоминания

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Method/asr/timezone/high-latitude/adjustments доступны | 🟡 | Backend profile полный; web UI показывает только часть |
| Результаты совпадают с golden cases | ✅ | Есть engine golden tests и pinned config/tzdb metadata |
| Координаты не логируются и не сохраняются без consent | ✅ | Calculate request redaction тестируется; `PrayerProfile` намеренно не содержит location fields |
| Локальные уведомления работают offline | ❌ | Правила хранятся, но клиентского scheduler нет |
| Timezone/location change перепланирует уведомления | ❌ | Device-local контракт есть, исполняющего клиента нет |

### Синхронизация

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Guest data не теряются после регистрации | ❌ | Нет account linking/guest merge endpoint |
| Bookmarks/positions/goals/reminders/playback sync | 🟡 | Bookmarks, positions, prayer profile и reminders есть; goals/playback отсутствуют |
| Повтор operation ID не создаёт дубликат | ✅ | Idempotency/fingerprint tests присутствуют |
| Tombstones не возвращают удалённые данные | ✅ | Bookmark/reminder tombstones и retired-ID ledgers реализованы |
| Full resync после expired cursor без потери outbox | ✅ | Snapshot token/restart/retention contract и tests реализованы на backend |

### Обратная связь

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Гость/пользователь создаёт ticket и безопасный attachment | 🟡 | Ticket работает для гостевой сессии; attachment model/upload отсутствует |
| Контекст контента автоматически связан | 🟡 | Immutable context schema и валидация есть; web-форма не передаёт полный route/content context |
| Религиозная ошибка получает ускоренный SLA | ✅ | Category routing, priority и SLA deadline покрыты tests |
| Operator reply, user notification, immutable history | 🟡 | Reply/history/audit есть; пользовательская notification delivery отсутствует |
| Ticket не меняет published content напрямую | ✅ | Feedback не имеет mutation path к Quran publication |

### Реклама и пожертвования

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Нет ads на запрещённых экранах | ❌ | Placement domain и tests отсутствуют |
| Campaign period/language/country/frequency/moderation | ❌ | Campaign domain отсутствует |
| Global ad kill switch | ❌ | Отсутствует |
| Donation allowlisted HTTPS redirect | ❌ | Отсутствует |
| Backend не хранит платёжные реквизиты | ❌ | Платёжного/redirect домена нет; критерий нельзя принять только по отсутствию функциональности |

### Качество и эксплуатация

| Критерий | Статус | Обоснование |
|---|:---:|---|
| OpenAPI и SDK/contracts проходят CI | 🟡 | OpenAPI validation есть; generated SDK/compatibility gate отсутствует |
| SLO доказаны на проектном пике | ❌ | Есть bounded 120-request smoke, но это не capacity/soak test |
| Restore drill подтверждает RPO/RTO | 🟡 | Backup/verify/restore-check реализованы; нет расписания и доказательства RPO 15 минут/RTO 4 часа |
| Нет critical/high vulnerabilities | 🟡 | Web production `npm audit` есть; полного backend/container SCA/image scan gate нет |
| Runbooks, dashboards и alerts доступны | 🟡 | Runbooks/metrics есть; dashboards/alerts отложены |
| Privacy/license/religious launch checklist пройден | ⏸ | Требует внешнего продуктового, правового и религиозно-редакционного sign-off |

## Исправления по итогам аудита

- Production env-шаблон приведён к фактическим именам настроек backend: удалены
  неиспользуемые параметры старой реализации, добавлены действующие TTL, rate limits,
  лимиты данных и retention-настройки.
- Документация prayer/reminders уточнена: backend хранит privacy-safe профиль и правила,
  но не координаты дома, рассчитанные времена молитв и не запускает device/push scheduler.
- Ссылка на этот аудит добавлена в корневой README, чтобы старый unchecked checklist больше
  не использовался как источник фактической готовности.

## Приоритетный backlog

### P0-A — точность Корана и release evidence

1. Добавить regression harness для ayah regions: structural sweep всех 604 страниц,
   viewport matrix в Playwright и curated визуальные cases сложных многосегментных аятов.
2. Добавить hizb/rub‘ al-hizb в dataset/model/API и полноценный переход по juz/ayah в web.
3. Зафиксировать content acceptance record: source/license review, религиозный reviewer,
   checksum принятой версии и критерии rollback.

Это следующий рекомендуемый блок: он локален, не требует bucket/monitoring и снижает самый
чувствительный риск — неверное сопоставление религиозного текста и интерактивной области.

### P0-B — account lifecycle и client foundation

1. Реализовать verified identity/login, account linking и transactional guest merge.
2. Создать Flutter workspace: secure storage, локальная БД, API client, durable outbox,
   sync bootstrap и базовый Mushaf reader.
3. Добавить Telegram Mini App auth validation и client shell либо оформить ADR об исключении
   Mini App из первого релиза.

### P0-C — offline/audio/prayer

1. Offline package manifests, resumable/checksummed installer и quota/eviction UI.
2. Player state machine: repeat/range, паузы, скорость, sleep timer, interruption recovery,
   background audio и system media controls.
3. Flutter local prayer parity и local notification scheduler с timezone/location reschedule.

### P0-D — продуктовые домены

1. RU/EN/AR i18n и полный RTL UI.
2. Translation/tafsir placeholder schema/API/UI.
3. Reading sessions, goals, streaks и playback-state sync.
4. Safe feedback attachments, user notifications и editorial approvals.
5. Ads/donation domains реализовывать последними, после утверждения policy/placements.

### P0-E — launch hardening

1. Backend/container dependency and image scanning, expanded browser/device matrix.
2. Capacity/soak test на staging и документирование SLO/RPO/RTO evidence.
3. Server/domain/TLS, privacy/license/religious sign-off.
4. Monitoring/dashboard/alerts и offsite bucket остаются отложенными по текущему решению,
   но блокируют широкий production launch.

## Не считать закрытым

- Наличие поля checksum без client installer не закрывает offline integrity.
- Наличие `AuthIdentity` model без link/login/merge endpoints не закрывает аккаунт.
- Хранение reminder rules без локального scheduler не означает работающие уведомления.
- Наличие metrics endpoint без dashboards/alerts не означает operational monitoring.
- Отсутствие ads/payments code не доказывает безопасность ещё не реализованного flow.
