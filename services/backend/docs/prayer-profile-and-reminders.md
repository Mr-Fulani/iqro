# Prayer profile and local reminders

Этот документ описывает персональный профиль расчёта намаза и правила локальных
напоминаний MVP. Контракт предназначен для Flutter, Next.js web и Next.js Telegram
Mini App.

## Граница ответственности

Backend:

- хранит выбранную версию метода расчёта, мазхаб Асра, high-latitude/polar правила,
  ручные поправки и timezone policy;
- синхронизирует намерение пользователя: молитва/чтение/повторение, дни недели,
  локальное время либо смещение от молитвы и короткий тип сигнала;
- обеспечивает optimistic concurrency, идемпотентность, tombstones, квоты и retention;
- никогда не хранит координаты, вычисленные occurrence times, push token или историю
  срабатываний в этом модуле.

Правила напоминаний являются сущностями общего sync v1 вместе с reading position и
закладками. Профиль намаза намеренно остаётся отдельным singleton endpoint: его нельзя
посылать как `entity_type` в `/api/v1/sync/push`.

Flutter рассчитывает ближайшие occurrence times и регистрирует локальные системные
уведомления. Web и Mini App в текущем срезе синхронизируют настройки и показывают
in-app напоминания только пока клиент активен. Server push, bot delivery, delivery log и
полный азан не входят в этот этап.

Все endpoint ниже требуют авторизацию. Все ответы, включая ошибки, получают
`Cache-Control: private, no-store, max-age=0`, `Pragma: no-cache`, `Expires: 0` и
`Vary: Authorization`.

## Профиль намаза

### GET /api/v1/me/prayer-profile

Возвращает единственный профиль пользователя. До первой записи возвращает `404` с
`code=prayer_profile_not_found`.

`method_available=false` означает, что сохранённая точная версия конфигурации была
отозвана, метод выключен либо её algorithm/tzdb version не поддерживается текущим
движком. Backend не подменяет её новым методом незаметно для пользователя. Клиент должен
показать предупреждение, перечитать `/api/v1/prayer/methods` и запросить явный выбор.

### PUT /api/v1/me/prayer-profile

PUT создаёт либо полностью заменяет профиль:

```json
{
  "base_revision": 0,
  "method_config_id": "019fe338-4958-7623-be5e-f330e5ef5aca",
  "method_checksum_sha256": "<64 lowercase hex characters>",
  "asr_method": "hanafi",
  "high_latitude_rule": "middle_of_night",
  "polar_resolution": "unresolved",
  "adjustments": {
    "fajr": 0,
    "sunrise": 0,
    "dhuhr": 0,
    "asr": 0,
    "maghrib": 0,
    "isha": 0
  },
  "timezone_mode": "device_local",
  "client_updated_at": "2026-08-09T12:00:00Z"
}
```

Для первого PUT передаётся `base_revision=0`, для изменения — ревизия последнего
принятого snapshot. Если функциональное состояние уже совпадает, повтор запроса успешен
даже со старой базовой ревизией и не увеличивает `revision`. Иное состояние со старой
ревизией даёт `409 prayer_profile_revision_conflict`.

Допустимы два timezone-режима:

- `device_local`: `fixed_timezone` передавать запрещено; профиль следует за текущим
  IANA timezone устройства;
- `fixed`: обязателен `fixed_timezone`, например `Europe/Istanbul`; identifier должен
  существовать в закреплённой backend-версии IANA tzdb.

`device_id` берётся только из проверенного access-token context. Клиент не может
передать или подменить его в JSON. Координаты, город, timezone offset и occurrence times
в профиле отсутствуют.

Прямые ORM-write операции для `PrayerProfile` запрещены прикладному коду: запись идёт
только через prayer-profile service. `save()` повторно проверяет domain-инварианты, но
`QuerySet.update()` по своей природе обходит model validation и допустим лишь в явно
проверенной data migration.

## Правила напоминаний

Endpoints:

- `GET /api/v1/me/reminders` — полный авторитетный snapshot, включая tombstones;
- `POST /api/v1/me/reminders` — создать правило с client-generated UUIDv7;
- `GET /api/v1/me/reminders/{id}` — получить одно правило;
- `PATCH /api/v1/me/reminders/{id}` — частично изменить правило;
- `DELETE /api/v1/me/reminders/{id}` — создать tombstone.

Максимум — 64 непросроченных правила и 256 записей с ещё не очищенными tombstones на
пользователя. Это hard bounds API, а не рекомендация для UI.

### Общая форма

```json
{
  "id": "019fe63b-2f58-766f-8a11-b913bb2d80c1",
  "base_revision": 0,
  "client_updated_at": "2026-08-09T12:00:00Z",
  "reminder_type": "prayer",
  "schedule": {
    "kind": "prayer",
    "prayer_event": "fajr",
    "prayer_offset_minutes": -10
  },
  "weekdays_mask": 127,
  "timezone": {"mode": "device_local"},
  "signal": "sound",
  "is_enabled": true
}
```

Неизвестные поля отклоняются на каждом уровне вложенности. Поля `device_id`, location,
coordinates, occurrence time, push token и произвольное имя звукового файла никогда не
принимаются.

Это ограничение относится к reminder payload. Web-клиент передаёт округлённые координаты
отдельно в device Web Push subscription только после явного browser permission. Координаты не
входят в `PrayerProfile` или reminder snapshot, не возвращаются status endpoint и удаляются при
отключении подписки. Для prayer rules сервер использует их вместе с versioned prayer profile,
чтобы поддерживать indexed очередь пяти ежедневных уведомлений.

Web-форма может хранить последнее выбранное место расчёта локально на устройстве, чтобы не
сбрасывать город после reload. Это локальное предпочтение не становится частью `PrayerProfile`
и попадает в Web Push subscription только после отдельного действия пользователя.

### Типы и расписания

`prayer` использует только prayer schedule:

```json
{
  "kind": "prayer",
  "prayer_event": "maghrib",
  "prayer_offset_minutes": 5
}
```

События: `fajr`, `dhuhr`, `asr`, `maghrib`, `isha`. Смещение — целое число от `-120`
до `120` минут. `sunrise` намеренно не является молитвой в reminder contract.

`quran_reading` использует локальное wall-clock time:

```json
{
  "reminder_type": "quran_reading",
  "schedule": {"kind": "local_time", "local_time": "07:30:00"}
}
```

`quran_review` дополнительно требует диапазон аятов:

```json
{
  "reminder_type": "quran_review",
  "schedule": {"kind": "local_time", "local_time": "20:00:00"},
  "review_target": {
    "start_ayah_id": "019fe63b-2f58-766f-8a11-b913bb2d80c2",
    "end_ayah_id": "019fe63b-2f58-766f-8a11-b913bb2d80c3"
  }
}
```

Backend принимает только аяты опубликованной активной версии Корана. Границы должны
принадлежать одной версии издания, а конец не может предшествовать началу. Draft и
superseded content возвращаются как несуществующие.

### Дни недели

`weekdays_mask` — битовая маска ISO-порядка, минимум `1`, максимум `127`:

| День | Бит | Значение |
| --- | ---: | ---: |
| Понедельник | 0 | 1 |
| Вторник | 1 | 2 |
| Среда | 2 | 4 |
| Четверг | 3 | 8 |
| Пятница | 4 | 16 |
| Суббота | 5 | 32 |
| Воскресенье | 6 | 64 |

Например, все дни — `127`, рабочие дни — `31`. Для prayer schedule маска относится к
локальной гражданской дате самой молитвы до применения offset.

### Timezone и сигнал

Timezone rule также является строгим union:

- `{"mode":"device_local"}` — следовать за timezone устройства;
- `{"mode":"fixed","name":"Europe/Istanbul"}` — сохранить точный IANA identifier.

Timezone конкретного reminder имеет приоритет над timezone профиля. Для prayer schedule
она задаёт гражданскую дату и timezone, передаваемые в расчёт; для local-time schedule —
wall-clock recurrence. `device_local` означает текущую IANA zone устройства в момент
планирования. Timezone профиля используется экраном намаза и как UI-default при создании
правила, но не переопределяет уже сохранённую timezone самого rule.

Координаты молитвенной локации остаются локальными. Если fixed prayer reminder не имеет
на устройстве явно выбранной локации, совместимой с этим timezone, клиент не должен
угадывать координаты или использовать текущее место путешественника: правило показывается
как требующее настройки и не планируется.

`signal` принимает только `silent`, `vibration` или `sound`. `sound` означает короткий
системный сигнал, выбранный и разрешённый клиентом/ОС. Полная аудиозапись азана — P1 и
не моделируется как произвольный URL или файл в MVP.

### Конкурентность и повторы

- POST требует UUIDv7 и `base_revision=0`. Точный повтор нормализованного create
  возвращает прежний объект с `200`; новое создание — `201`.
- PATCH требует `base_revision>=1`. Повтор уже применённого функционального состояния
  возвращает прежний snapshot без новой ревизии.
- Конкурирующее изменение старой ревизии возвращает `409 reminder_revision_conflict`.
- DELETE требует последнюю ревизию, очищает scheduling payload и повышает ревизию.
  Повтор DELETE возвращает тот же tombstone.
- Tombstone нельзя PATCH-ить или создать повторно: используется `410 reminder_deleted`
  либо, после удаления компактного ledger, `409 reminder_id_not_reusable`.

Новый UUIDv7 должен быть не старше 360 дней и не более чем на 24 часа впереди серверных
часов. Это ограничение гарантирует, что физическое удаление старого tombstone не позволит
вернуть давно удалённую identity.

### Единый sync v1

Offline-клиент может отправлять те же изменения через `POST /api/v1/sync/push` с
`entity_type=reminder`. Внутри sync-envelope:

- `entity_id` — UUIDv7 правила;
- `action=upsert`, `base_revision=0` и полный functional payload создают правило;
- `action=upsert`, `base_revision>=1` и частичный functional payload изменяют его;
- `action=delete`, `base_revision>=1` и пустой/отсутствующий payload создают tombstone;
- `client_updated_at` находится во внешней операции, а `id`, `base_revision`,
  `client_updated_at` и `device_id` никогда не дублируются в payload.

Форма functional payload совпадает с direct API: `reminder_type`, `schedule`,
`review_target`, `weekdays_mask`, `timezone`, `signal`, `is_enabled`. Вложенные union
объекты заменяются целиком. `device_id` определяется access token; сохранённое во внешнем
sync-envelope поле для reminder запрещено, чтобы клиент не мог подменить provenance.

Точное повторение нормализованной операции с тем же `operation_id` возвращает сохранённый
outcome/cursor с `replayed=true`, подставляет текущий user-owned snapshot и ничего не
записывает. Другой запрос с тем же operation ID даёт `409 sync_operation_reuse`;
разрешение конфликта всегда получает новый operation ID.
Реальные create/patch/delete через direct endpoints и sync атомарно записывают один и тот
же глобальный change-log. No-op, exact retry и повторное удаление tombstone не создают
новую ревизию или cursor.

Incremental pull возвращает полный reminder snapshot с discriminator
`entity_type=reminder`; для delete это минимизированный tombstone, а не `null`.
При delete прежние retained changes этой identity также схлопываются в минимизированный
tombstone, поэтому obsolete schedule/timezone/ayah/device data не остаются в change-log.
`SyncOperation` хранит outcome/cursor без дублирования functional snapshot.
Конфликты `revision_mismatch`, `entity_missing`, `entity_id_unavailable`,
`entity_id_not_reusable` и `reminder_quota_exceeded` возвращаются внутри result
конкретной операции. Ошибка формы payload, timezone или ayah откатывает весь batch.

### Полный snapshot и tombstones

`GET /api/v1/me/reminders` возвращает:

```json
{
  "mode": "full_snapshot",
  "authoritative": true,
  "generated_at": "2026-08-09T12:00:00Z",
  "count": 2,
  "reminders": []
}
```

Snapshot является полным, а не cursor delta. Клиент должен:

1. upsert локальные записи по `id` и максимальной принятой `revision`;
2. отменить системное уведомление для каждого `deleted_at != null`;
3. удалить локальные записи, отсутствующие в завершённом авторитетном snapshot;
4. только после успешного reconciliation планировать новый rolling horizon.

Удалённая запись минимизирована: `schedule=null`, `review_target=null`, device/timezone
name/ayah links очищены, сигнал становится `silent`, `is_enabled=false`. Через 365 дней
tombstone физически заменяется компактной записью identity ledger. Hourly Celery task
обрабатывает ограниченные batch; операторский dry-run:

```bash
uv run python manage.py prune_reminder_tombstones --dry-run
```

Общий full resync (`GET /api/v1/sync/pull?full_resync=true`) проходит фазы reading
position, bookmark, затем reminder и включает активные правила и tombstones. Signed
`next_page_token` фиксирует snapshot cursor и текущую фазу. Отсутствие записи становится
авторитетным только после получения последней страницы; до этого клиент не удаляет
локальные правила и не отменяет уведомления из-за промежуточного неполного списка.

Отдельный `GET /api/v1/me/reminders` остаётся компактным авторитетным snapshot только
правил напоминаний. Он полезен клиенту, которому не требуется полный reading-state sync,
но не образует отдельную конкурирующую историю: обе поверхности читают те же revision и
tombstones.

Физическое удаление reminder tombstone разрешено только после удаления всех retained
`SyncChange` и `SyncOperation` этой identity. Сначала транзакционно создаётся компактный
`RetiredReminderId`; поэтому старый UUID нельзя воскресить. Exact replay действует в
пределах retention окна `SyncOperation`, а физическое удаление tombstone ждёт окончания
этого окна. После pruning завершённый full resync сообщает старое удаление авторитетным
отсутствием.

## Планирование на Flutter

Рекомендуемый local-first алгоритм:

1. получить каталог методов, профиль и reminder snapshot;
2. проверить `method_available`, checksum, algorithm/tzdb versions и разрешения ОС;
3. получить координаты только на устройстве и не помещать их в analytics/logs;
4. рассчитать prayer events на ограниченный rolling horizon;
5. применить weekday mask, prayer offset либо local wall-clock time;
6. зарегистрировать локальные уведомления со стабильным локальным идентификатором,
   производным от `(reminder_id, civil_date, event)`;
7. атомарно заменить предыдущий локальный план и сохранить версии входов.

Outbox и локальное optimistic state сохраняются атомарно; до terminal result клиент не
меняет `operation_id`. Для одной identity держится не более одной незавершённой операции,
а несколько offline-правок схлопываются в желаемое состояние. При
`revision_mismatch` клиент принимает серверный snapshot, повторно накладывает локальное
намерение и отправляет новую операцию с новой base revision и новым operation ID.

Cursor из ответа push нельзя записывать как локальный pull cursor: между прежним cursor и
push могли находиться изменения другого устройства. После push клиент продолжает pull от
своего прежнего сохранённого cursor до `has_more=false`. При истёкшем cursor незавершённый
outbox сохраняется, full resync собирается во временное состояние до последней страницы,
после чего outbox перебазируется. Tombstone сразу отменяет локальное системное
уведомление; перепланирование выполняется только после reconciliation и отдельного
получения prayer profile.

Полный replan нужен при изменении профиля/rule revision, даты, координат, IANA timezone,
UTC offset/DST, разрешений, метода/checksum, algorithm/tzdb version, после перезагрузки
устройства и после обновления приложения. При `unresolved` polar result нельзя угадывать
время или ставить уведомление по старому соседнему дню.

### Обязательные timezone/DST-векторы

Реализации Flutter/Next должны проходить одинаковые conformance-векторы:

1. Профиль `fixed=Europe/Istanbul`, prayer rule `fixed=Europe/Berlin`: effective zone —
   `Europe/Berlin`; weekday mask относится к дате молитвы в Berlin до применения offset.
   Если тот же rule имеет `device_local`, а устройство находится в `Asia/Tokyo`, effective
   zone — `Asia/Tokyo`.
2. `Europe/Berlin`, local-time `02:30`, `2026-03-29` (DST gap): выполнить ровно один раз
   в первый существующий wall-clock instant не раньше заданного, то есть `03:00+02:00`.
   Не пропускать весь день и не переносить на предыдущий UTC offset.
3. `Europe/Berlin`, local-time `02:30`, `2026-10-25` (DST fold): выполнить ровно один
   раз в первое вхождение `02:30`, то есть `02:30+02:00`; второе `02:30+01:00` не
   планировать.

Prayer event приходит из расчётного движка как однозначный timestamp с offset и не
применяет wall-clock gap/fold disambiguation повторно.

На iOS локальное уведомление после регистрации доставляет система, в том числе когда
приложение не запущено; изменившиеся запросы необходимо отменять и создавать заново — см.
[Apple: Scheduling a notification locally](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

На Android точные alarm требуют отдельного обоснования и, для соответствующих версий ОС,
специального доступа. Клиент должен проверять право, уметь перепланировать после его
отзыва/перезагрузки и явно деградировать к разрешённому поведению — см.
[Android: Schedule alarms](https://developer.android.com/develop/background-work/services/alarms).

## Web и Telegram Mini App

Обычный web push требует Service Worker, push subscription и явного разрешения; этот
backend-срез ещё не хранит subscriptions и не обещает доставку после закрытия страницы.
Архитектурная основа браузерного механизма описана в
[MDN Push API](https://developer.mozilla.org/en-US/docs/Web/API/Push_API).

Telegram Mini App может запросить право бота писать пользователю, но это отдельный
consent и server-delivery канал, а не фоновый JavaScript timer внутри закрытого WebView.
Текущий MVP только синхронизирует правило. Будущий bot delivery обязан использовать
`requestWriteAccess` и учитывать отказ пользователя — см.
[Telegram Mini Apps](https://core.telegram.org/bots/webapps).

## Основные ошибки

| HTTP | Code | Значение |
| ---: | --- | --- |
| 400 | `invalid` | неизвестное поле, неверный union/range/timezone/ayah |
| 404 | `prayer_profile_not_found`, `reminder_not_found` | ресурс пользователя отсутствует |
| 409 | `*_revision_conflict` | нужно перечитать snapshot и разрешить конфликт |
| 409 | `prayer_method_checksum_mismatch` | обновить каталог методов |
| 409 | `reminder_quota_exceeded` | достигнут hard limit |
| 409 | `reminder_id_not_reusable` | сгенерировать свежий UUIDv7 |
| 410 | `prayer_method_withdrawn`, `reminder_deleted` | конфигурация/identity больше не активна |
| 422 | `prayer_rule_unsupported` | метод не поддерживает выбранное правило |
| 429 | `*_rate_limited` | учитывать `Retry-After` |
