# P0/MVP gap audit

Дата аудита: 25 августа 2026 года

Аудируемый baseline: репозиторий после backend+web среза локализации от 25 августа 2026 года

Источник требований: [утверждённое ТЗ](../thoughts/shared/specs/2026-08-09-quran-platform-backend.md)

Целевая архитектура роста: [architecture and scaling](architecture-and-scaling.md).
Последовательность работ: [план и roadmap](roadmap.md).

Для ограниченного публичного Web MVP 25 августа 2026 года принят fast-track: дополнительные
production-sized/load/soak исследования перенесены после релиза, поскольку budget S0 уже имеет
нижнюю измеренную границу. Это решение не меняет оценку полного multi-client MVP и не снимает
content/license/religious, monitoring, offsite backup, security и rollback gates. Scope,
компенсирующие меры и стоп-условия: [Web MVP fast-track](release/web-mvp-fast-track-2026-08-25.md).

## Правила оценки

- ✅ **Готово** — требование реализовано и подтверждается кодом, данными и тестом/проверкой.
- 🟡 **Частично** — полезный вертикальный срез есть, но полное P0-требование или один из
  обязательных клиентов не закрыт.
- ❌ **Нет** — домен или обязательный клиентский сценарий отсутствует.
- ⏸ **Внешний gate** — реализация зависит от лицензии, редакционного или launch sign-off.

Статус оценивается по полному многоклиентскому MVP (Flutter, web и Telegram Mini App),
поэтому работоспособный web-preview сам по себе не закрывает Flutter/offline критерии.
Изменения требований фиксируются новой версией ТЗ; этот документ остаётся status overlay и
не выдаёт запланированную архитектуру за реализованную функциональность.

## Краткий итог

| Срез | Готово | Частично | Нет | Внешний gate |
|---|---:|---:|---:|---:|
| 18 P0-групп | 3 | 11 | 4 | 0 |
| 36 критериев приёмки | 10 | 14 | 10 | 2 |

Сильная часть текущего baseline — канонический Quran dataset, публичное Quran/audio API,
гостевая и verified-email сессии, transactional guest merge, позиции/закладки, надёжная
offline-синхронизация серверного состояния, prayer engine/profile, local-only reminder rules,
feedback, account lifecycle, расширенный web-аудиоплеер, четырёхъязычный web UI и production
runtime. Основной незакрытый объём находится в Flutter, offline packages, локальном планировщике
уведомлений, клиентском i18n parity и отсутствующих контентных/коммерческих доменах.

## Доказательная база

- Dataset `madani-hafs@1.0.2`: 114 сур, 6 236 аятов, 604 страницы, 30 джузов,
  60 хизбов, 240 четвертей и 12 346 региональных сегментов; source commits и SHA-256 закреплены в
  [source lock](../services/backend/docs/quran-sources.lock.json) и dataset manifest.
- В media-каталоге присутствуют 604 versioned WebP-страницы и asset manifest с SHA-256.
- Backend предоставляет Quran, audio, guest auth, reading/sync, prayer/profile,
  reminders, feedback, health/metrics и OpenAPI endpoints.
- Полный backend test suite: 545 passed, 6 skipped; суммарное покрытие 84,76%.
- Web имеет 48 Playwright cases, включая verified-email merge без credentials в
  `localStorage`, bookmark revision contracts, reporter feedback lifecycle, prayer-profile и
  reminder contracts, durable sync outbox/cursor/full-resync, многосегментный аят 6:2,
  viewport matrix 375/768/1440 px, переходы по juz/hizb/rub/ayah, расширенный аудиоплеер,
  persistent dock с паузой и сохранением позиции при route navigation,
  device revoke, grace-period account deletion/cancel, переключение RU/EN/AR/TR, сохранение
  locale, browser-language negotiation, locale-prefixed RU/EN/AR/TR routes, арабский RTL,
  canonical/hreflang/page metadata, private `noindex`, robots/localized sitemap/manifest/social
  assets, server-rendered глубокие страницы опубликованных сур/аятов, versioned Quran content
  sitemap с отсечением draft/stale versions, server-rendered каталог опубликованных чтецов и
  декламаций, versioned audio sitemap только для streamable complete releases и переход с
  иллюстративного аватара чтеца на выбранный аудиокаталог.
- Production Compose ранее прошёл isolated runtime smoke: migrations/static gates,
  frontend/API/media, HTTPS proxy path, resource limits и 120/120 read-only запросов.
- Live web smoke development-окружения повторно подтвердил загрузку Quran.Foundation catalog,
  114 треков выбранной декламации, таймкоды и реальное воспроизведение первой суры. Это не
  заменяет versioned manifests и внешний лицензионный/religious release evidence.
- Staging backend 25 августа 2026 года успешно прошёл отдельную read-only авторизацию в
  Quran.Foundation production API и получил каталог из 21 chapter reciter. Credentials хранятся
  только в закрытом staging env; sync выключен, аудиоданные не импортированы и не опубликованы.

## Матрица P0

| # | Требование P0 | Статус | Реализовано | Для полного P0 не хватает |
|---:|---|:---:|---|---|
| 1 | Гостевой режим и единый аккаунт | 🟡 | Guest bootstrap, passwordless verified email, linking/reauth, transactional guest merge, device-bound rotation, HttpOnly web BFF, session restore, device inventory/selective revoke, logout-all и self-service deletion с grace period | Identity unlink/change safeguards и дополнительные OAuth providers |
| 2 | RU/EN/AR и RTL | 🟡 | Backend и web поддерживают RU/EN/AR/TR: типизированный каталог, browser-language negotiation, cookie/account persistence, language switch, динамические `lang`/`dir`, арабский RTL и локализованные product/error flows | Нет Flutter и Telegram Mini App parity |
| 3 | Мадинский Мусхаф Хафс, 604 страницы | ✅ | Versioned dataset, 114/6 236/604/30, source lock, checksums, 604 WebP assets | До публичного релиза всё ещё нужен религиозно-редакционный и лицензионный sign-off |
| 4 | Навигация по page/surah/ayah/juz/hizb/rub | ✅ | Dataset/model/API/web поддерживают 30 джузов, 60 хизбов, 240 четвертей и точный переход по аяту/странице/суре | — |
| 5 | Интерактивные области аятов | 🟡 | 12 346 сегментов, полный structural audit 604 страниц, группировка сегментов, E2E 6:2 и viewport matrix | Нужна ручная религиозно-редакционная приёмка curated сложных страниц |
| 6 | Позиции, закладки, история, цели, серии | 🟡 | Position, bookmarks, revisions, tombstones и sync | Нет reading sessions/history, goals и streaks |
| 7 | Несколько чтецов, streaming и offline audio | 🟡 | QF catalog/sync, immutable logical tracks и economy/standard/high renditions, compatible default asset, 114 surah tracks, ayah timings, R2/CDN ADR, create-only S3 upload и CDN evidence gate | Не доказаны три полностью лицензированных multi-quality релиза; production R2/CDN ещё не provisioned и corpus не загружен; нет transcoding, управляемой offline-установки, клиентского quality policy и redistribution pipeline |
| 8 | Repeat/range/pause/speed/sleep timer | ✅ | Web: повтор аята и суры/диапазона, диапазоны аятов, паузы 0–5 с, скорость 0,5–2,0×, таймер после аята или 5–60 минут; persistent dock сохраняет трек и позицию, ставя playback на паузу при route navigation | — |
| 9 | Flutter background playback/media controls | ❌ | — | Flutter workspace и platform audio service отсутствуют |
| 10 | Offline packages и восстановление sync | 🟡 | Idempotent push/pull, conflicts, cursors, full resync, tombstones и web durable outbox для reading/bookmarks/reminders | Нет package domain/manifest API, resumable installer, локального entity cache и полноценного offline Flutter-клиента |
| 11 | Заглушки переводов и тафсиров | ❌ | — | Нет `translations`/`tafsir` models, API и placeholder UI |
| 12 | Намаз, методы, мазхаб, поправки | 🟡 | Versioned methods/releases, engine, golden cases, privacy-safe profile, high-latitude/polar rules и полный web profile UI | Flutter local parity и региональный content review отсутствуют |
| 13 | Локальные уведомления и напоминания | 🟡 | Prayer/reading/review rules, revisions, retention и sync; web Web Push исполняет все три типа при закрытой вкладке, пять намазов включаются отдельными ежедневными тумблерами, location хранится только после opt-in на device subscription, а profile/timezone/location перепланируют очередь | Нет полностью offline/native Flutter scheduler; Web Push требует сеть |
| 14 | Управляемая реклама | ❌ | Только feedback context/category для жалобы на рекламу | Нет campaign/creative/placement/frequency cap/moderation/kill-switch домена |
| 15 | Внешние donation links | ❌ | Только feedback category для жалобы на ссылку | Нет allowlist, safe redirect, admin workflow и клиентского placement |
| 16 | Feedback и editorial workflow | 🟡 | Tickets, immutable context/messages/audit, SLA routing, operator admin и web reporter thread с close/reopen | Нет безопасных attachments, user notifications и editorial change request/review/approval workflow |
| 17 | Django Admin и специальные admin API | 🟡 | 30 model registrations для реализованных доменов | Нет полной role matrix, MFA/break-glass safeguards и административных разделов отсутствующих доменов |
| 18 | Observability, backup, audit, CI/CD | 🟡 | Health/readiness, bounded multi-worker API metrics, versioned opt-in Prometheus/Grafana/Alertmanager dashboard/rules, structured privacy logging, CI, single-host production Compose, local backup/verify/restore drill, load-smoke, staged read-only public web/API, bounded audio Range, fail-closed auth/sync и mixed capacity harness, PgBouncer budget, раздельные Redis roles, stateless API/workers, Redis-lease для Beat, общий Next.js Redis cache/tag coordination, bounded gateway public-JSON cache с защищённым purge и временно проверенный single-host `2 API + 2 web` scale/failover | Нет production-like capacity/soak proof, provider CDN/billing/QoE ingestion, внешнего uptime и проверенной alert delivery, multi-host deployment/load balancer и offsite backup |

## Критерии приёмки

### Коран

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Утверждённое опубликованное издание 114/30/604 | 🟡 | Технический артефакт полный; нет зафиксированного религиозного и лицензионного acceptance record |
| Assets и канонические данные прошли integrity pipeline | ✅ | Source lock, per-file/asset SHA-256, builder/import/publication tests |
| Переход к любой суре, аяту, джузу и странице | ✅ | API и web UI покрывают все четыре адресации, а также hizb/rub |
| Стабильный выбор области на поддерживаемых размерах | 🟡 | Structural sweep и viewport matrix пройдены; остаётся ручная content acceptance |
| Позиция восстанавливается локально и на другом устройстве | 🟡 | Backend cross-device revisions/sync реализованы; registered cross-client flow отсутствует |

### Аудио

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Минимум три полностью лицензированных чтеца | ⏸ | API не ограничивает количество, но production rights/sign-off не зафиксирован в репозитории |
| Stream/offline/repeat/range/speed/pause/timer | 🟡 | Streaming и все перечисленные режимы плеера есть на web; управляемый offline installer отсутствует |
| Flutter background/lock-screen controls | ❌ | Flutter отсутствует |
| Корректное восстановление после interruption | 🟡 | Web сохраняет курсор при pause/waiting, явно возобновляет его и покрыт E2E; native audio focus/device tests отсутствуют |
| Повреждённый файл не устанавливается | ❌ | Checksums присутствуют в контракте, но client package installer отсутствует |

### Намаз и напоминания

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Method/asr/timezone/high-latitude/adjustments доступны | 🟡 | Backend и web profile UI закрывают полный контракт; Flutter local parity отсутствует |
| Результаты совпадают с golden cases | ✅ | Есть engine golden tests и pinned config/tzdb metadata |
| Координаты не логируются и не сохраняются без consent | ✅ | Calculate request redaction тестируется; `PrayerProfile` не содержит location fields, а округлённые координаты появляются только в device Web Push subscription после отдельного browser permission |
| Локальные уведомления работают offline | 🟡 | Web Push доставляет prayer/reading/review при закрытой вкладке, но требует сеть; полноценный offline scheduler остаётся задачей Flutter |
| Timezone/location change перепланирует уведомления | 🟡 | Web-подписка обновляет IANA timezone при открытии кабинета; location можно обновить явно, а изменение prayer profile перепланирует серверную очередь; native reschedule отсутствует |

### Синхронизация

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Guest data не теряются после регистрации | ✅ | Verified-email вход транзакционно переносит позиции, закладки, reminders, профиль, feedback и устройства; merge и rollback покрыты тестами |
| Bookmarks/positions/goals/reminders/playback sync | 🟡 | Bookmarks, positions, prayer profile и reminders есть; goals/playback отсутствуют |
| Повтор operation ID не создаёт дубликат | ✅ | Idempotency/fingerprint tests присутствуют |
| Tombstones не возвращают удалённые данные | ✅ | Bookmark/reminder tombstones и retired-ID ledgers реализованы |
| Full resync после expired cursor без потери outbox | ✅ | Backend token/restart/retention contract и web постраничный recovery с rebase/pull покрыты тестами |

### Обратная связь

| Критерий | Статус | Обоснование |
|---|:---:|---|
| Гость/пользователь создаёт ticket и безопасный attachment | 🟡 | Ticket работает для гостевой сессии; attachment model/upload отсутствует |
| Контекст контента автоматически связан | 🟡 | Web передаёт route/app/platform context; Quran/audio/prayer coordinates пока не прикладываются автоматически |
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
| SLO доказаны на проектном пике | 🟡 | Strict budget CX23 Quran read подтвердил 10 saturated clients: 4 612 запросов за 2 минуты, 0% ошибок, p95 682 ms; 12 clients превысили p95. Synthetic warm R2 audio доказал 25 playback clients и деградацию с 30; bounded one-shot real-audio probe подтвердил delivery 3/3 QF assets, но metadata consistency только 2/3; изолированный guest auth/reading sync подтвердил 8 тяжёлых stateful clients и p95 boundary на 10; realistic mixed — `20 readers + 4 sync users` без ошибок; new registered email account + sync — 4 active users с boundary на 6/8. Полный разрешённый multi-surah audio release, existing-account/multi-device identity и production-sized S0/S1 ещё не измерены |
| Restore drill подтверждает RPO/RTO | 🟡 | Backup/verify/restore-check реализованы; нет расписания и доказательства RPO 15 минут/RTO 4 часа |
| Нет critical/high vulnerabilities | 🟡 | Блокирующие `npm audit`, hash-verified backend `pip-audit` и Trivy для всех пяти production-образов добавлены; нужен зелёный GitHub CI на release commit |
| Web performance/a11y regression budget | ✅ | Lighthouse блокирует регрессии на standalone production build для landing RU/EN/AR/TR и опубликованной суры RU/AR, включая RTL, Core Web Vitals и resource budgets |
| Browser E2E проверяет deployable web artifact | 🟡 | Все 62 сценария проходят на dev/standalone; реальный staging smoke подтвердил RU/EN/AR/TR locale metadata, Quran shell, EN/TR audio/prayer/login/404 и SEO; временная noindex-активация dataset подтвердила content-backed SSR/API, но полный production browser journey ещё открыт |
| Runbooks, dashboards и alerts доступны | 🟡 | Versioned dashboard/rules и runbook готовы; production deployment, provider telemetry, on-call ownership и synthetic delivery ещё не подтверждены |
| Privacy/license/religious launch checklist пройден | ⏸ | Требует внешнего продуктового, правового и религиозно-редакционного sign-off |

## Исправления по итогам аудита

- Production env-шаблон приведён к фактическим именам настроек backend: удалены
  неиспользуемые параметры старой реализации, добавлены действующие TTL, rate limits,
  лимиты данных и retention-настройки.
- Документация prayer/reminders уточнена: versioned профиль не содержит location, а округлённые
  координаты сохраняются только после отдельного browser consent внутри device Web Push
  subscription. Масштабируемая очередь исполняет prayer/reading/review; рассчитанные времена не
  входят в публичные snapshots.
- Ссылка на этот аудит добавлена в корневой README, чтобы старый unchecked checklist больше
  не использовался как источник фактической готовности.
- Web bookmark/feedback contracts приведены к OpenAPI: bookmark PATCH/DELETE используют
  revision protocol, feedback поддерживает paginated list, UUIDv7 idempotency, reporter messages,
  close/reopen и отображение публичной переписки.
- Web prayer-profile и reminder contracts подключены полностью: revisioned method/asr/high-latitude/
  polar/adjustment/timezone profile и CRUD правил prayer/Quran reading/Quran review. Для всех
  трёх типов добавлены VAPID Web Push, Service Worker, indexed due queue, bounded retry,
  browser permission/disable и автоматическое обновление locale/timezone; prayer дополнительно
  требует отдельный location opt-in и пересчитывается после изменения профиля/location.
- Web sync доведён до полного transport lifecycle: user-scoped durable outbox без credentials,
  `push` с conflict rebase/remap, постраничный incremental pull, cursor-expiry/full-resync recovery,
  сохранение pull-курсора и guest-outbox flush до email merge. Live PostgreSQL проверка выполнена
  внутри транзакции с rollback.
- Account lifecycle закрыт backend+web вертикально: `/me` восстанавливается через HttpOnly BFF,
  кабинет показывает устройства, выборочно отзывает чужую installation-сессию, отдельно
  подтверждает `logout-all`, а удаление/отмена требуют нового email-кода. Pending account
  изолирован от продуктовых API; bounded Celery-финализатор после 7-дневного grace period удаляет
  синхронизируемые данные и анонимизирует audit shell.
- Web-аудиоплеер использует единый segment state machine в каталоге и Мусхафе: repeat ayah/
  selection, диапазоны, учебные паузы, скорость, sleep timer, сохранение позиции при browser
  interruption и Media Session actions. Это не заявляет OS background playback.
- Backend и web локализованы на RU/EN/AR/TR: locale валидируется и сохраняется для пользователя
  и устройства, SSR выбирает язык из cookie или `Accept-Language`, переключатель сохраняет выбор,
  а арабский режим задаёт `lang=ar`, `dir=rtl` и логическое RTL-выравнивание. Flutter/TMA parity
  остаётся отдельной клиентской задачей.
- Web публикует стабильные locale-prefixed server-rendered маршруты суры и аята с часовым
  revalidated data cache. Server Component получает
  только активную опубликованную edition/version через внутренний public API, основной арабский
  текст и ссылки присутствуют в исходном HTML, а versioned Quran sitemap строится из того же
  backend publication boundary. По той же схеме опубликованы список сур, каталог чтецов,
  страницы чтеца/декламации и versioned audio sitemap; интерактивные reader/player остаются
  отдельными client surfaces.

## Приоритетный backlog

### P0-A — точность Корана и release evidence

1. ✅ Regression harness для ayah regions: structural sweep всех 604 страниц, viewport
   matrix в Playwright и закреплённый многосегментный case 6:2.
2. ✅ Hizb/rub‘ al-hizb добавлены в dataset/model/API; web переходит по juz/hizb/rub/ayah.
3. 🟡 [Content acceptance record](quran-content-acceptance.md) создан с checksum и rollback;
   полный dataset и 604 WebP повторно проверены и временно активированы только на noindex staging
   для content-backed load test; религиозный, юридический и product sign-off остаются внешними
   production release gates.

Техническая часть блока закрыта. Production-активация остаётся заблокированной до нового
provenance-safe immutable кандидата и трёх внешних sign-off из content acceptance record.

### P0-B — account lifecycle и client foundation

1. ✅ Verified email login/linking, device proof, HttpOnly web-session, transactional guest
   merge, inventory/selective revoke и grace-period deletion/cancel реализованы; identity
   unlink/change и дополнительные providers остаются последующим hardening.
2. Создать Flutter workspace: secure storage, локальная БД, API client, durable outbox,
   sync bootstrap и базовый Mushaf reader.
3. Добавить Telegram Mini App auth validation и client shell либо оформить ADR об исключении
   Mini App из первого релиза.

### P0-C — offline/audio/prayer

1. Offline package manifests, resumable/checksummed installer и quota/eviction UI.
2. ✅ Web player state machine: repeat/range, паузы, скорость, sleep timer, browser interruption
   recovery и Media Session controls. Flutter background audio, native audio focus и system
   media controls остаются отдельной mobile-задачей.
3. ✅ Web Push для prayer/Quran reading/review при закрытой вкладке, включая отдельный location
   opt-in и пять ежедневных prayer toggles. Flutter local prayer parity и полностью offline
   notification scheduler остаются следующей задачей.

### P0-D — продуктовые домены

1. ✅ Backend+web RU/EN/AR/TR i18n и полный RTL UI; Flutter/TMA parity остаётся в client backlog.
2. Translation/tafsir placeholder schema/API/UI.
3. Reading sessions, goals, streaks и playback-state sync.
4. Safe feedback attachments, user notifications и editorial approvals.
5. Ads/donation domains реализовывать последними, после утверждения policy/placements.

### P0-E — launch hardening

1. Зелёный dependency/image gate на release commit и expanded browser/device matrix.
2. 🟡 Capacity/soak test на staging и документирование SLO/RPO/RTO evidence.
   Quran HTML/API часть подтверждена
   [strict budget CX23 отчётом](capacity/staging-cx23-quran-budget-2026-08-25.md): 10 saturated
   clients, 4 612 запросов за две минуты, 0% ошибок, p95 682 ms; 12 clients превысили p95.
   Synthetic warm R2 audio
   подтвердил 25 playback clients; изолированный
   [guest sync отчёт](capacity/staging-cx23-stateful-sync-2026-08-25.md) — 8 тяжёлых stateful
   clients и latency boundary на 10; [mixed отчёт](capacity/staging-cx23-mixed-realistic-2026-08-25.md)
   — `20 readers + 4 sync users` без ошибок; [registered отчёт](capacity/staging-cx23-registered-user-2026-08-25.md)
   — 4 active new-account users с boundary на 6/8. Реальный audio release,
   existing-account/multi-device identity и production-sized повтор остаются открыты.
3. Server/domain/TLS, privacy/license/religious sign-off.
   Budget CX23, `staging.iqro.forum`, automatic TLS proxy, isolated secrets/test email,
   backup drill и pre-publication evidence уже есть. Отдельный R2 staging bucket/scoped token/CORS,
   custom media hostname, edge TLS и hostname-scoped cache/security rules активны; CDN contract и
   cache HIT доказаны. Quran dataset временно активирован только на noindex staging для
   технического теста, но provenance-safe production candidate, принятый аудиорелиз и финальные
   content sign-off ещё отсутствуют.
4. Развернуть готовый monitoring baseline, подключить внешний uptime/provider telemetry,
   проверить alert delivery; offsite bucket также блокирует широкий production launch.

### P0-F — scalable platform foundation

1. Code-side immutable object storage/CDN pipeline и отказ production runtime от local media
   готовы; provision R2/custom domain/CORS, загрузка принятого corpus и restore/inventory drill
   остаются deployment-gate. Production Compose пока остаётся S0 single-host профилем.
2. Schema/API logical track и bitrate/codec renditions уже разделены; добавить реальные
   transcoded/лицензированные варианты, клиентский выбор качества и egress budget alerts.
3. Edge-cache текущих Quran/audio/prayer catalog endpoint'ов без cookie/`Authorization` и
   защищённый purge готовы; при появлении `library` остаётся добавить его publication event и
   contract tests. Персональные ответы остаются `private, no-store`.
4. PgBouncer-compatible connection budget, stateless API/workers, token-safe Redis lease для
   singleton Beat, отдельно конфигурируемые Redis roles и общий Next.js cache/tag coordination
   готовы; budget single-host Quran capacity и временный `2+2` scale drill доказаны, остаётся
   production-like multi-host deployment.
5. Capacity harness готов; CX23 Quran read-only baseline доказан. До заявления профиля S1 для
   10 000 DAU добавить реальную модель трафика, audio/auth/sync workload и production-sized soak;
   S2/S3 ресурсы не покупать до фактических triggers.

### P1 — functional expansion после multi-client MVP

1. `memorization`: карточки слов, аятов и диапазонов, versioned content references,
   интервальное повторение и offline review queue Flutter.
2. `dua`: отдельные сборники, источники, переводы, категории, publication и manifests.
3. `library/search`: типизированные read-модели дуа, хадисов, книг и образовательных
   подборок без универсальной таблицы контента.
4. Каждый новый домен проходит extension contract: license/source, versioning, review,
   rollback, API cache, sync/offline, audit и cross-client contract tests.

## Не считать закрытым

- Наличие поля checksum без client installer не закрывает offline integrity.
- Verified email, guest merge и device/deletion lifecycle не закрывают безопасную смену/unlink
  identity и дополнительные OAuth providers.
- Наличие Web Push для prayer/reading/review не означает полностью offline-доставку без сети или
  готовый native mobile scheduler.
- Наличие versioned metrics/dashboard/rules без deployment, внешней телеметрии и проверенной
  доставки alert не означает operational monitoring.
- Отсутствие ads/payments code не доказывает безопасность ещё не реализованного flow.
