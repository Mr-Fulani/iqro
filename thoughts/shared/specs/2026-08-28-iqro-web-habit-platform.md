# Iqro Web Habit Platform — продуктовая спецификация

- Дата: 28 августа 2026 года
- Статус: подтверждено владельцем продукта, готово к планированию реализации
- Первый клиент: Web
- Следующие клиенты: Flutter, затем Telegram Mini App

## 1. Executive Summary

Iqro развивается из функциональной Quran-платформы в международного помощника для
начинающих мусульман. Первый конкурентный вертикальный срез соединяет три действия в один
ежедневный цикл: продолжить чтение, понять аят через проверенный перевод или тафсир и
выполнить личную норму.

Web-клиент первым показывает возможности backend, но бизнес-контракты остаются
client-independent. Flutter и Telegram Mini App будут использовать те же доменные модели,
API и правила прогресса без копирования бизнес-логики.

Эта спецификация расширяет, а не заменяет:

- [backend-спецификацию](2026-08-09-quran-platform-backend.md);
- [roadmap](../../../docs/roadmap.md);
- [архитектуру масштабирования](../../../docs/architecture-and-scaling.md);
- [MVP gap audit](../../../docs/mvp-gap-audit.md).

При конфликте правила точности религиозного контента, лицензирования, приватности и
публикации из backend-спецификации имеют приоритет.

## 2. Problem Statement

У начинающего мусульманина обычно нет единого спокойного сценария, который помогает:

1. быстро вернуться к месту чтения;
2. понять смысл прочитанного на своём языке;
3. выбрать реалистичную дневную норму;
4. видеть прогресс без давления и сравнения с другими;
5. продолжать практику регулярно.

Текущий продукт уже умеет показывать Мусхаф, синхронизировать позицию и закладки,
воспроизводить Коран, выбирать чтеца, рассчитывать времена намаза и отправлять напоминания.
Два главных продуктовых пробела подтверждены MVP gap audit:

- отсутствуют versioned translations/tafsir models, API и пользовательский Study UI;
- отсутствуют reading sessions, reading goals, daily progress и streaks.

Без этих возможностей приложение остаётся хорошей читалкой и плеером, но не формирует
устойчивую ежедневную привычку и уступает продуктам, соединяющим чтение, понимание и цели.

## 3. Product Goals

### 3.1. Главная цель

Помочь пользователю читать Коран регулярно, начиная с небольшой личной нормы и не требуя
регистрации до появления потребности в синхронизации.

### 3.2. Продуктовое обещание

Пользователь должен пройти цикл «открыл → продолжил → понял → выполнил норму → вернулся
завтра» без необходимости разбираться в сложных настройках.

### 3.3. Неизменяемые продуктовые принципы

- Религиозный текст и его понимание важнее вовлечения, монетизации и декоративных функций.
- Основной религиозный контент бесплатен и доступен гостю.
- Прогресс мотивирует лично; публичных рейтингов и сравнения пользователей нет.
- Источник, авторство, версия и статус проверки контента всегда прослеживаются.
- Функция не публикуется как готовая, пока нет работающего сквозного сценария.
- Интерфейс начинающего пользователя прост по умолчанию, а дополнительные возможности
  раскрываются по запросу.
- RU, EN, AR и TR являются равноправными стартовыми локалями; Arabic получает полноценный
  RTL, а не зеркально сломанный LTR-интерфейс.

## 4. Success Criteria

### 4.1. Primary metric

W1 3-day reader rate: доля активированных пользователей, у которых есть квалифицированное
чтение минимум в три разные локальные даты в течение первых семи локальных дат, начиная с
даты первой квалифицированной сессии.

Активированный пользователь — гостевая установка или зарегистрированный пользователь,
завершивший первую квалифицированную сессию.

### 4.2. Secondary metrics

- D7 reading return: доля активированных пользователей с квалифицированным чтением на
  седьмую локальную дату.
- Daily goal completion rate: доля user-days с активной целью, в которые цель выполнена.
- Qualified reading sessions per active reader per week.
- Goal creation rate после первой квалифицированной сессии.
- Study adoption: доля читателей, включивших перевод или открывших тафсир.
- Sync conversion: доля активных гостей, зарегистрировавшихся для сохранения прогресса на
  нескольких устройствах.

### 4.3. Metric guardrails

- Метрики считаются только для cohort, допустимой действующей consent policy; в отчёте
  показывается coverage, чтобы не выдавать выборку за всю аудиторию.
- Системой истины для целей и серий служат reading domain records, а не ненадёжные
  browser-events.
- Analytics не получает текст заметок, избранного, запросов, координаты, точный аят или
  религиозный профиль пользователя.
- Прослушивание аудио само по себе не считается чтением.

### 4.4. Release acceptance

P0 считается продуктово завершённым, когда новый гость может:

1. открыть локализованную главную страницу;
2. начать или продолжить чтение;
3. увидеть рекомендованный проверенный смысловой ресурс возле аята;
4. создать одну ежедневную цель;
5. получить прогресс автоматически либо добавить бумажное чтение вручную;
6. выполнить норму и увидеть завершённый день;
7. зарегистрироваться и сохранить прогресс без потери гостевых данных.

## 5. Users and Stakeholders

### 5.1. Primary persona

Начинающий мусульманин, который:

- может не знать арабский язык;
- читает нерегулярно или не знает, с какой нормы начать;
- использует телефон или web;
- ожидает объяснимый и спокойный интерфейс;
- хочет понимать смысл, слушать правильное чтение и видеть личный прогресс.

### 5.2. Secondary personas

- Регулярный читатель, которому нужен быстрый Continue, перевод, тафсир и синхронизация.
- Пользователь бумажного Мусхафа, который хочет учитывать чтение вручную.
- Пользователь с Arabic UI, которому нужен корректный RTL и арабский поясняющий ресурс.
- Редактор контента, который управляет импортом, атрибуцией, review и публикацией.
- Религиозный рецензент, который в будущем утверждает конкретную версию ресурса.
- Оператор платформы, который следит за импортами, SLO, feature flags и откатами.

## 6. Information Architecture

### 6.1. Основные группы

Главная страница использует расширяемый каталог возможностей:

1. Сегодня:
   - продолжить чтение;
   - дневная норма;
   - ближайшее напоминание.
2. Основное:
   - Коран;
   - Прослушивание;
   - Дуа;
   - Планировщик;
   - Избранное.
3. Повседневное:
   - Времена намаза.
4. Знания:
   - Тафсир;
   - Книги;
   - Хадисы.
5. Обучение и интерактив:
   - Заучивание;
   - Вопросы и ответы;
   - Квизы.

### 6.2. Статусы возможностей

Каждая возможность имеет один публичный статус:

- available — сквозной сценарий работает;
- beta — функция работает, но явно обозначены ограничения;
- coming_soon — карточка рассказывает о будущем сценарии, но не имитирует работающую функцию;
- hidden — функция не показывается пользователю.

Coming soon не индексируется как готовая контентная страница и не ведёт на пустой экран.

### 6.3. Поведение главной

- Новый посетитель сначала видит ценность платформы и понятные действия «Читать Коран» и
  «Слушать».
- Вернувшийся пользователь сначала видит персональный блок «Сегодня», затем общий каталог.
- Ошибка персонального API не блокирует публичный каталог и вход в Коран.
- Персональный блок не попадает в CDN/ISR cache и не встраивается в публичный HTML.

## 7. Core User Journeys

### 7.1. Первый визит гостя

1. Сайт определяет locale из URL; автоматическая подсказка языка не меняет URL без согласия.
2. Пользователь видит краткое обещание продукта, основные доступные функции и будущие
   возможности.
3. Пользователь нажимает «Читать Коран».
4. Открывается последняя локальная позиция либо безопасное начало по умолчанию.
5. Для RU, EN и TR рекомендованный перевод включён по умолчанию; для AR по умолчанию
   доступен рекомендованный краткий арабский тафсир.
6. После квалифицированного чтения предлагается небольшая ежедневная цель.
7. Прогресс гостя сохраняется для этой установки; регистрация не навязывается.

### 7.2. Возвращение

1. Пользователь открывает главную.
2. Блок «Сегодня» показывает Continue, текущую норму и прогресс.
3. Continue открывает явно сохранённую последнюю позицию.
4. Квалифицированная сессия увеличивает прогресс.
5. При достижении нормы день отмечается выполненным без конфетти, звука или давления.

### 7.3. Изучение аята

1. Арабский текст остаётся главным и визуально неизменяемым слоем.
2. Пользователь включает или выключает рекомендованный перевод.
3. Пользователь раскрывает тафсир отдельно; длинный тафсир не разворачивается автоматически.
4. Можно выбрать другой опубликованный ресурс из разрешённого списка.
5. Рядом доступны автор, источник и атрибуция.
6. Недоступность дополнительного ресурса не скрывает арабский текст.

### 7.4. Создание цели

1. После первой сессии или в Планировщике пользователь выбирает единицу:
   минуты, страницы либо аяты.
2. Пользователь задаёт положительную дневную норму.
3. В P0 одновременно активна только одна цель чтения.
4. Новая цель заменяет активную только после явного подтверждения; история не удаляется.
5. Напоминание предлагается отдельно и требует своего permission/consent.

### 7.5. Бумажный Мусхаф

1. Пользователь выбирает «Добавить чтение вручную».
2. Форма по умолчанию использует единицу активной цели.
3. Пользователь вводит положительное значение, локальную дату и необязательную ссылку на
   диапазон.
4. Запись сохраняется с source=manual и никогда не маскируется под автоматическую.
5. Изменение или удаление записи пересчитывает progress и streak идемпотентно.

### 7.6. Регистрация и синхронизация

1. Гость видит ненавязчивое объяснение пользы аккаунта: несколько устройств и восстановление.
2. После регистрации гостевые position, bookmarks, goal и sessions объединяются с аккаунтом.
3. Повтор операции merge не создаёт дублей и не увеличивает прогресс второй раз.
4. Конфликт цели разрешается явным правилом: сохраняется более новая активная цель, старая
   архивируется; история сессий объединяется по client-generated ID.

## 8. Functional Requirements

## 8.1. Must Have — P0

### P0-A. Каталог возможностей и новая главная

- Backend website domain хранит стабильный capability key, группу, статус, sort order,
  icon key, список поддерживаемых клиентов и необязательный feature flag.
- Локализованные title, description и CTA хранятся отдельно для RU, EN, AR и TR.
- Клиенты маппят стабильный capability key на собственный route; backend не раздаёт
  произвольный исполняемый deep link.
- Публичный API возвращает только разрешённые поля и cacheable catalog response.
- Web не содержит отдельные несвязанные массивы карточек для hero, navigation и каталога.
- Returning-home получает personal Today отдельным private, no-store запросом.

Критерии приёмки:

- изменение статуса available/beta/coming_soon/hidden не требует переписывать layout;
- карточки корректно отображаются во всех четырёх locale;
- Arabic layout проходит RTL e2e;
- недоступность Today API не ломает публичную главную;
- скрытый модуль отсутствует в UI и sitemap.

### P0-B. Versioned translations and tafsir

В translations domain добавляются явные сущности:

- TranslationResource;
- TranslationVersion;
- AyahTranslation;
- TafsirResource;
- TafsirVersion;
- TafsirEntry;
- LocaleStudyDefault.

Обязательные поля ресурса:

- provider и provider_resource_id;
- language и direction;
- author/organization;
- display title;
- source URL;
- attribution text;
- license/terms reference;
- upstream cache/sync policy;
- availability state.

Обязательные поля версии:

- immutable version identifier;
- upstream revision/checkpoint и checksum;
- imported_at;
- draft/review/published/withdrawn status;
- sanitizer version;
- review evidence;
- published_at и withdrawn_at.

Правила:

- импорт никогда не обновляет опубликованный текст на месте;
- новый upstream snapshot создаёт новую draft version;
- публичный API видит только published version;
- удаление или ошибка upstream не удаляет последнюю утверждённую версию автоматически;
- HTML/footnotes проходят allowlist sanitation, bidi и XSS tests;
- публичный API предназначен для отображения внутри продукта и не превращается в raw bulk
  redistribution endpoint;
- Content Sync Quran.Foundation выполняется не реже требуемого provider policy интервала;
  целевой интервал — семь дней;
- provider outage оставляет последний разрешённый контент доступным и создаёт operator alert;
- каждый ответ Study API содержит attribution и version identifier.

Locale defaults:

- RU, EN и TR получают по одному рекомендованному опубликованному переводу;
- AR получает один рекомендованный краткий арабский тафсир;
- дополнительные ресурсы появляются только после license, editorial и religious approval;
- конкретные resource IDs являются release configuration и фиксируются отдельным sign-off,
  а не зашиваются в UI.

Publication gate:

- до появления религиозного рецензента importer, models, admin, fixtures и draft preview
  разрабатываются полностью;
- production publication новой translation/tafsir version запрещена без review evidence;
- временное отключение ресурса выполняется feature flag или withdrawal без релиза клиента.

Критерии приёмки:

- повторный импорт одного checkpoint идемпотентен;
- изменение одного текста создаёт новую version и diff;
- draft не выдаётся публичным endpoint;
- withdrawal исключает ресурс из default selection, но сохраняет audit/history;
- все 6 236 canonical ayahs имеют ожидаемое покрытие либо версия fail-closed не публикуется;
- на каждом отображении доступна атрибуция;
- test payload не может внедрить script, event handler или опасный URL.

### P0-C. Study view в Коране

- Arabic Quran text и Mushaf остаются независимы от переводов и тафсира.
- Перевод можно включать и выключать во время чтения.
- Тафсир открывается по запросу и не перегружает reader по умолчанию.
- Выбор ресурса хранится локально для гостя и синхронизируется как preference после
  регистрации.
- Существующий Quran audio player продолжает работать рядом со Study UI.
- Пропавший перевод/тафсир показывает локализованное состояние ошибки и кнопку повтора, но
  не блокирует Arabic Quran.
- Footnotes доступны с клавиатуры и screen reader.

Критерии приёмки:

- один и тот же ayah reference возвращает согласованные Quran, translation и tafsir versions;
- смена locale выбирает locale default, если пользователь ранее не сделал явный совместимый
  выбор;
- сохранённый выбор withdrawn resource безопасно возвращается к locale default;
- reader остаётся пригоден без JavaScript в индексируемой published-surah surface, а
  интерактивный Study UI подключается как client island.

### P0-D. Reading sessions

ReadingSession содержит:

- client-generated UUID;
- user/guest owner и device;
- source: automatic или manual;
- status: active, completed, discarded;
- started_at, ended_at, local_date и timezone snapshot;
- start/end Quran references, если известны;
- active_seconds;
- credited_pages и credited_ayahs;
- manual_metric и manual_amount для ручной записи;
- client_updated_at, revision и idempotency data.

Правила automatic session:

- время учитывается только когда reader находится foreground и документ видим;
- hidden/background time и простой audio playback не начисляют reading minutes;
- rapid scrolling без минимального активного взаимодействия не начисляет страницы/аяты;
- повторная доставка одного события не увеличивает счётчик;
- session становится qualified при наличии минимум 60 active seconds или положительного
  подтверждённого content progress;
- технические thresholds versioned/configurable, но изменение версии не переписывает старые
  raw sessions без явного recalculation.

Правила manual session:

- amount строго больше нуля;
- source всегда manual;
- значение учитывается только для своей metric и не конвертируется приблизительно между
  минутами, страницами и аятами;
- future local date запрещена;
- допустимое backdate-окно P0 — семь локальных дней;
- create/update/delete идемпотентны и аудитируемы.

### P0-E. Daily goal, progress and streak

ReadingGoal содержит metric, target, daily cadence, timezone, start/end dates, status,
revision и device metadata. В P0 действует максимум одна active reading goal на owner.

GoalProgress содержит goal, local_date, achieved amount, completed_at, contributing session
IDs и recalculation version.

Streak является производным материализованным состоянием: current, longest,
last_qualifying_local_date и recalculation version.

Правила:

- цель считается выполненной один раз при amount >= target;
- сверх нормы сохраняется в daily amount, но не переносится на следующий день;
- timezone change действует на новые записи и не отнимает уже завершённые дни;
- pause/archive цели не удаляет историю;
- reset streak является явным действием и не удаляет sessions;
- удаление contributing manual session может снять completion и пересчитать streak;
- публичных leaderboard, shame copy и автоматических социальных публикаций нет.

Критерии приёмки:

- конкурентные session updates не приводят к double counting;
- progress одинаков после incremental update и full recalculation;
- переход через local midnight покрыт тестами;
- DST, смена timezone и повтор merge покрыты тестами;
- пользователь может удалить history/goal в соответствии с data-rights policy.

### P0-F. Today API и Planner UI

Client-independent endpoints:

- GET /api/v1/me/today;
- GET/PUT/DELETE /api/v1/me/reading-goal;
- POST/PATCH/DELETE /api/v1/me/reading-sessions/{id};
- POST /api/v1/me/reading-sessions/manual;
- GET /api/v1/me/reading-history;
- GET /api/v1/translations;
- GET /api/v1/tafsirs;
- GET /api/v1/quran/ayahs/{ayah_key}/study.

Точные paths могут быть приведены к действующим conventions при реализации, но OpenAPI
operations и client semantics остаются такими.

Today response включает:

- continue reference;
- active goal;
- today progress;
- completion state;
- streak summary;
- ближайшее чтение/reminder summary без раскрытия push capability secret.

Критерии приёмки:

- персональные endpoints имеют private, no-store;
- writes используют idempotency/revision contract;
- guest-to-account merge не теряет данные;
- API пригоден для будущих Flutter и Telegram adapters без web-only полей.

### P0-G. Privacy-safe product analytics

Архитектура:

- operational telemetry, product analytics и ad reporting разделены;
- web отправляет first-party allowlisted versioned events в backend batch endpoint;
- transactional outbox отделяет приём события от sink/export;
- первый sink может использовать PostgreSQL и daily aggregates;
- sink заменяется на ClickHouse, BigQuery или другой warehouse без изменения client event
  contract;
- сторонний advertising SDK не встраивается в reader.

Разрешённые P0 events:

- home_viewed;
- capability_opened;
- reading_started;
- reading_session_qualified;
- goal_created;
- goal_completed;
- study_resource_toggled;
- account_sync_enabled.

Разрешённые dimensions:

- event schema version;
- locale;
- client type и app version;
- anonymous installation/user pseudonym;
- goal metric без target value;
- session source;
- capability key;
- coarse device class.

Запрещённые properties:

- Quran position, surah/ayah key и content text;
- note, bookmark и favorite content;
- точный timestamp привычки в аналитическом экспорте сверх необходимого event time;
- координаты и prayer profile;
- email, имя, access token, push endpoint;
- search/query text;
- advertising ID или religious interest profile.

Raw product analytics хранится не более 90 дней, затем удаляется или превращается в
обезличенный aggregate согласно действующей policy. Отзыв consent прекращает будущий
необязательный сбор без потери основной функции.

### P0-H. Localization, accessibility and beginner UX

- Весь новый пользовательский текст существует на RU, EN, AR и TR.
- Arabic использует dir=rtl на document/layout уровне; Arabic Quran block сохраняет
  корректное направление и внутри LTR locale.
- Нет publication machine translation без review.
- Интерактивные элементы доступны с клавиатуры, имеют focus state и понятное accessible name.
- Progress не передаётся только цветом.
- Reduced motion поддерживается во всех новых переходах.
- Empty, loading, error, offline и withdrawn-content states локализованы.
- Beginner defaults не требуют предварительной настройки.

## 8.2. Should Have — P1

### P1-A. Атмосферный режим прослушивания

- Quran recitation и nature ambience являются независимыми audio sources.
- Поддерживаются отдельные gain controls, mute и master stop.
- Nature ambience выключен по умолчанию и запускается только после user gesture.
- Разрешены только звуки природы без музыки и человеческих голосов.
- Первый набор: дождь и море; каждый asset проходит license и moderation.
- Visual layer использует лёгкую анимацию, static fallback, prefers-reduced-motion и
  data-saver policy.
- Quran timing, repeat, queue и Media Session не зависят от ambience/visual layer.
- Web честно сообщает, что browser suspension может остановить background mix; полноценный
  background audio является преимуществом будущего Flutter-клиента.

### P1-B. План заучивания

- Reading goal и memorization plan остаются разными доменами и могут существовать
  одновременно.
- Memorization добавляет target ranges, repetition schedule и review queue.
- Повторное чтение для заучивания не искажает обычную reading streak.

### P1-C. Расширение Study

- Несколько одобренных переводов одновременно.
- Word-by-word translations и morphology после отдельного source/sign-off.
- Сравнение версий без превращения интерфейса начинающего в сложный research tool.
- Offline packages для разрешённых translations/tafsirs.

## 8.3. Nice to Have — P2

- Типизированная библиотека книг и хадисов.
- Расширенные коллекции и тематические подборки.
- Модерируемый раздел вопросов и ответов.
- Квизы по выбранным темам.
- Дополнительные nature scenes и ambient assets.
- Telegram Mini App capability parity.
- Полноценный Flutter offline/background experience.

Каждый религиозный домен получает собственные source, version, editorial, publication и
feedback rules; универсальная таблица религиозного контента запрещена.

## 9. Technical Architecture

### 9.1. Component boundaries

- quran: canonical editions, surahs, ayahs, pages and coordinates.
- translations: translation/tafsir catalogs, versions, entries, attribution and provider sync.
- reading: position, bookmark, session, goal, progress, streak and sync semantics.
- website: capability catalog and localized presentation metadata.
- reminders: reading reminder rules and delivery; не вычисляет goal progress.
- audio: reciters, recitations, tracks, timings and playback; P1 ambience is a separate
  presentation/media type.
- accounts: registered/guest identity, device, consent and merge orchestration.
- analytics: allowlisted events, consent gate, outbox and aggregates.
- editorial/audit: review, publication, withdrawal and privileged action evidence.

Домены взаимодействуют через public services, immutable IDs и outbox events. UI не читает
provider API напрямую.

### 9.2. High-level flow

Public content:

Quran.Foundation Content Sync → draft import → validation/sanitization → editorial and
religious approval → immutable published version → public API/cache → Web Study UI.

Personal progress:

Web reader/manual form → idempotent reading service → ReadingSession → GoalProgress
recalculation → Streak snapshot → private Today API → Web Today UI.

Analytics:

Allowlisted client/domain event → consent gate → transactional outbox → configured sink →
daily aggregate dashboard.

### 9.3. Consistency

- Database transaction commits session mutation, progress recalculation and outbox event
  atomically where practical.
- GoalProgress has a uniqueness constraint on goal + local_date.
- Session uses client-generated identity and owner-scoped uniqueness.
- Recalculation is deterministic and safe to repeat.
- Public content cache keys include resource and version.
- Publication event invalidates only affected tags/resources.

### 9.4. Guest and registered state

- Guest religious content requires no account.
- Текущий guest identity mechanism может использоваться как технический owner, но UI не
  обещает cross-device sync до регистрации.
- Guest preferences and progress survive ordinary navigation and offline periods on the same
  installation.
- Registration invokes the existing merge architecture extended for goals and sessions.
- Personal responses never use public cache.

### 9.5. Provider integration

Quran.Foundation is the primary dynamic provider for Mushaf positioning, Quran audio,
reciters, translations and tafsir where license and resource quality allow publication.

Integration requirements:

- credentials exist only backend-side;
- catalog discovery and content sync are separate jobs;
- jobs support checkpoint/resume, retry with jitter and bounded concurrency;
- upstream data is validated against canonical Quran references;
- unknown/deleted resources fail closed;
- last approved version remains during transient outage;
- operator sees sync age, coverage, validation failures and publication status;
- provider terms, attribution and redistribution limits are enforceable configuration.

Current local scan/Tanzil pipeline remains independent and is not silently mixed with
Quran.Foundation versions.

### 9.6. API and client contracts

- REST remains under /api/v1 and OpenAPI 3.1 is generated from code.
- JSON uses snake_case; time uses UTC ISO 8601, local_date and IANA timezone.
- Public catalog/study responses are cacheable only when versioned and free of personal data.
- Personal reads/writes are private, no-store.
- Flutter and Telegram consume generated or contract-tested clients.
- Web-only route names, component state and CSS concepts do not enter API schema.

## 10. Security, Privacy and Trust

- Public Quran, translation and tafsir reads do not require login.
- Admin import, preview, review, publish and withdraw actions use role-based permissions.
- Редактор не может сам выдать себе approval религиозного рецензента.
- Published content is immutable; correction creates a new version.
- Audit includes actor, action, reason, previous/new version and time.
- Provider HTML is untrusted input and always sanitized.
- CSP, output escaping, URL allowlists and bidi tests apply to translated content.
- CSRF/auth/revision/idempotency controls follow existing platform contracts.
- Optional analytics requires applicable consent and never gates core functionality.
- User can export/delete personal progress and withdraw consent.
- Final retention and lawful-basis decisions are approved before production for target
  jurisdictions; implementation keeps retention configurable.

## 11. Monetization Extension Points

Монетизация не входит в P0/P1 этой спецификации, но архитектура не должна блокировать:

- внешние allowlisted donation links без хранения payment credentials;
- subscription entitlements для дополнительных удобств;
- first-party moderated sponsorship placements в разрешённых нерелигиозных зонах.

Независимо от будущей модели:

- Quran text, базовые переводы/тафсир и основная практика чтения остаются бесплатными;
- ads запрещены в Mushaf, Study, tafsir, dua, prayer, audio player и notifications;
- religious habits не используются для targeting;
- вся advertising subsystem отключается global kill switch;
- изменение коммерческой модели требует отдельного license и legal review.

## 12. Non-Functional Requirements

### 12.1. Performance

Новый срез наследует platform SLO:

- public cached read p95 ≤ 300 ms;
- authenticated write p95 ≤ 500 ms;
- ordinary API p99 ≤ 1 000 ms;
- 5xx < 0.5% за пять минут;
- personal Today response не создаёт N+1;
- home/Study routes остаются в действующих Lighthouse budgets;
- translation/tafsir datasets не загружаются целиком в browser.

### 12.2. Scalability

- S0 beta: до 1 000 DAU без преждевременной покупки S3 resources.
- S1 launch: до 10 000 DAU и до 300 peak origin API RPS после cache.
- Архитектурный предел: 100 000 DAU по существующему S0–S3 plan.
- API/web/workers stateless; scheduled importer/beat singleton защищён lease.
- Append-only sessions/events имеют measured rows/day, retention и partition trigger.
- Переход мощности выполняется по saturation/capacity evidence, а не прогнозу DAU.

### 12.3. Reliability

- Public Quran остаётся доступным при падении personal/analytics services.
- Last approved translation/tafsir остаётся доступной при transient provider outage.
- Analytics failure не ломает reading write.
- Progress recalculation можно безопасно повторить из sessions.
- Backup, PITR, RPO 15 минут и RTO 4 часа наследуются из backend specification.
- Feature flags позволяют отключить Study resource, Today writes или analytics export
  независимо.

### 12.4. Quality

- Unit tests: domain invariants, timezone, idempotency, merge and recalculation.
- Contract tests: public Study, personal Today and write APIs.
- Import tests: fixtures, coverage, checksum, sanitation, checkpoint and withdrawal.
- E2E: first visit, Continue, create goal, automatic progress, manual progress,
  completion, registration merge, offline/error and Arabic RTL.
- Accessibility gate не ниже текущего Lighthouse threshold 0.95.
- Production publication требует content/license/religious sign-off.

## 13. Error and Edge States

- Provider unavailable: serve last approved content; alert if sync age exceeds policy.
- Resource withdrawn: stop defaulting to it and show approved fallback.
- Partial resource coverage: fail closed; не смешивать версии незаметно.
- No translation for locale: Quran remains available; clearly explain temporary limitation.
- Today API unavailable: show public home and local Continue if safe.
- Duplicate session request: return previous idempotent outcome.
- Concurrent goal updates: revision conflict with user-friendly refresh/retry.
- Local midnight during session: split credited progress by local date at boundary.
- Timezone change: future attribution uses new timezone; achieved past days remain achieved
  unless user explicitly edits source data.
- Browser closes mid-session: finalize last acknowledged heartbeat; do not invent background
  time.
- Offline guest: keep bounded local queue and retry idempotently.
- Manual future date or non-positive amount: reject inline without losing form input.
- Deleted manual entry: recalculate affected progress and streak.
- Registration merge conflict: deterministic merge report, no silent data loss.
- Reduced motion/data saver: static visual, no ambient/video preload.

## 14. Delivery Slices

### Slice 1 — Reading habit backend and minimal Today

Первый рекомендуемый implementation package:

1. ReadingSession, ReadingGoal, GoalProgress и Streak models/migrations.
2. Domain services для automatic/manual session, goal mutation и deterministic recalculation.
3. Today/goal/session API и OpenAPI tests.
4. Минимальный Web Today block и goal setup.
5. Guest-to-account merge tests.

Результат: пользователь уже может поставить норму, учитывать чтение и видеть выполненный
день без зависимости от незакрытого religious review.

### Slice 2 — Translation/tafsir foundation

1. translations domain models/admin.
2. Quran.Foundation catalog/sync adapter.
3. sanitation, coverage and immutable version tests.
4. draft preview и publication gate.
5. публичный catalog/Study API на fixtures до утверждения production resources.

### Slice 3 — Study UI and modular home

1. Translation toggle и expandable tafsir.
2. Locale defaults/fallback.
3. Capability catalog API/admin.
4. New-vs-returning home composition.
5. RU/EN/AR/TR and accessibility e2e.

### Slice 4 — Metrics and release hardening

1. Allowlisted event contract, consent gate and outbox.
2. W1/D7/goal aggregates with coverage.
3. Capacity, security, privacy and content sign-offs.
4. Canary release and rollback/withdrawal drill.

### Slice 5 — P1 listening atmosphere

Nature audio mixer, visual layer, reduced-motion/data-saver behavior and cross-browser tests.

## 15. Out of Scope for P0

- Тяжёлые video backgrounds и гарантированный web background mix.
- План заучивания и spaced repetition.
- Word-by-word и morphology.
- Полный offline translation/tafsir package.
- Книги, хадисы и универсальный library search.
- Вопросы и ответы.
- Квизы.
- Социальные рейтинги и sharing streak by default.
- Платежи внутри backend.
- Подписка, paywall, реклама и donation UI.
- Flutter и Telegram UI implementation.
- Публикация непроверенного религиозного ресурса ради соблюдения срока.

## 16. Open Questions for Implementation and Fixed Decisions

Блокирующих открытых продуктовых вопросов нет. Зафиксировано:

- аудитория — международные начинающие мусульмане;
- основная задача — регулярное чтение;
- platform order — Web, Flutter, Telegram Mini App;
- locale — RU, EN, AR, TR;
- guest content — полный;
- account value — cross-device sync/recovery;
- одна активная daily reading goal;
- units — minutes/pages/ayahs;
- manual paper reading — поддерживается и маркируется отдельно;
- translations/tafsir — один locale default, alternatives после approval;
- analytics — first-party, consent-aware, provider-neutral;
- monetization — отдельные extensions, не Quran core;
- отсутствующий religious reviewer — publication gate, не development blocker.

Конкретный выбор production translation/tafsir resource IDs не является открытым продуктовым
вопросом:
это контролируемые release data, которые обязаны пройти license/editorial/religious sign-off.
До sign-off используются draft fixtures и закрытый preview.

## 17. Appendix: Research Findings

### 17.1. Provider

Исследование Quran.Foundation Content API v4 показало наличие:

- Quran/Mushaf resources и positioning;
- reciters, chapter audio и ayah-by-ayah audio;
- translations на многих языках;
- tafsir;
- word-by-word resources;
- search и связанных Quran study resources.

Provider terms требуют корректной атрибуции, соблюдения cache/sync policy и запрещают
превращать display integration в неконтролируемую raw redistribution. Поэтому provider
content проходит через backend catalog, version, validation и publication pipeline.

### 17.2. Competitive patterns

Исследование Quran.com, Tarteel, Quranly, Ayah и Al Quran показало устойчивые ожидания рынка:

- быстрый Continue;
- translations/tafsir рядом с Quran;
- выбор чтеца и качественный player;
- personal goals, streaks и reminders;
- bookmarks/collections;
- memorization support;
- offline/mobile continuity.

Конкурентная позиция Iqro строится не на количестве карточек, а на цельном beginner journey,
международной локализации, строгом content trust и общей масштабируемой backend-платформе для
Web, Flutter и Telegram.

## 18. Definition of Done

Каждый delivery slice считается завершённым только если:

- acceptance criteria реализованы и покрыты тестами;
- OpenAPI и generated/client contracts обновлены;
- RU/EN/AR/TR copy и Arabic RTL проверены;
- accessibility и reduced-motion проверены;
- privacy/cache headers соответствуют типу данных;
- migrations обратимы или имеют документированный forward recovery;
- observability не содержит sensitive data;
- feature flag/rollback path проверен;
- roadmap и MVP gap audit обновлены по факту, а не заранее;
- для опубликованного религиозного контента приложены license/editorial/religious evidence.
