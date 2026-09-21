# Роадмап разделения аудиосценариев

Статус: implementation in progress

Дата начала: 2026-09-21

## Цель

Разделить независимые сценарии аудио:

- обычное прослушивание во вкладке «Аудио»;
- воспроизведение по аятам в Мусхафе и Reader;
- заучивание с повторениями и паузами.

Один и тот же человек может иметь несколько версий чтения. Возможности должны
принадлежать конкретной версии аудио, а не профилю чтеца.

## Ограничения проекта

- Backend остаётся client-independent API для Flutter, web и Telegram Mini App.
- Flutter использует одну Dart-кодовую базу для Android, iPhone и iPad.
- Django не проксирует аудиобайты; managed assets идут через object storage/CDN,
  внешние provider assets остаются внешними HTTPS URL.
- Публичные versioned audio assets неизменяемы; исправление публикуется новой версией.
- Текущие незакоммиченные изменения пользователя нельзя откатывать или очищать.
- Новые API-поля должны быть additive и совместимыми со старыми клиентами.

## Целевая модель

### Backend

Сохраняются уровни:

- `Reciter` — канонический профиль человека;
- `RecitationEdition` либо универсальный audio variant — конкретная версия чтения;
- `AudioTrack` — логический трек;
- `AudioRendition` — качество и физическая доставка;
- `AudioTimingVersion` и ayah segments — проверенные метаданные таймлайна.

Публичный каталог дополнительно сообщает:

```json
{
  "capabilities": {
    "listen": true,
    "ayah_playback": false,
    "memorization": false,
    "offline": true
  },
  "coverage": {
    "surah_tracks": 114,
    "timed_ayahs": 0,
    "expected_ayahs": 6236,
    "timings_complete": false
  }
}
```

`timings.available` сохраняется для обратной совместимости, но новые клиенты используют
capabilities и coverage. Источник без таймкодов может быть `listen`, но не должен попадать
в Mushaf/Ayah или Memorization.

Quran.Foundation ayah-by-ayah и будущие источники подключаются через typed delivery
adapter/resolver с единым стабильным идентификатором выбранного audio variant. Нельзя
создавать отдельную UI-логику для каждого провайдера.

### Flutter

Настройки разделяются по ролям:

- `listeningRecitationId`;
- `mushafRecitationId`;
- `memorizationDefaultRecitationId`.

Точный `recitation_id` активного плана заучивания остаётся главным источником выбора для
этого плана.

Воспроизведение разделяется на логические каналы:

| Канал | Persistence | Global mini-player / Media Session |
|---|---|---|
| Listening | local + remote position | Да |
| Mushaf | экранное, без global resume | Нет либо временная политика |
| Memorization | только состояние плана/экрана | Нет |

Общими остаются `PlaybackCore`, source resolver, clipping, speed, repeat и обработка
interruption. `PlaybackCoordinator` отвечает за ownership каналов. Если один физический
player не позволяет сохранить независимый Media Session widget, contextual playback должен
использовать lazy foreground player без дублирования бизнес-логики.

## Этапы внедрения

### 0. Стабилизация diff и ADR

- Сохранить текущие незакоммиченные изменения без отката.
- Отделить audio/memorization изменения от независимых plan/prayer изменений.
- Описать ADR для capabilities, универсального audio variant и playback channels.
- Зафиксировать матрицу вариантов: timed, untimed, partial, managed, external,
  ayah-by-ayah, offline.

Gate: согласованы DTO, error codes, migration policy и Media Session policy.

### 1. Backend contract

- Добавить capabilities и полную coverage в audio DTO.
- Вынести availability в selectors/service.
- Усилить проверку выбора recitation для Memorization.
- Проверять Quran edition и наличие выбранного ayah range.
- Сохранить старые audio endpoints и поля для совместимости.
- Добавить typed adapter/resolver для внешних ayah-by-ayah источников.
- Обновить OpenAPI и `services/backend/docs/audio-api.md`.

Проверки: audio models, selectors, serializers, API, memorization, migrations, QF sync,
media contract, query budget и OpenAPI validation.

### 2. Flutter data and preferences

- Расширить audio models новыми capability/coverage полями.
- Добавить role-aware selection API в `AudioRepository`.
- Мигрировать старый `reader_recitation_id` без потери выбора пользователя.
- Убрать использование одной preference из Audio, Mushaf, Reader и Memorization.
- Не изменять preference Listening при выборе чтеца в Memorization.

Проверки: DTO parsing, preference migration, role filtering, exact variant fallback,
withdrawn/unknown variant handling.

### 3. Playback coordinator

- Превратить текущий source flag в явные logical channels.
- Отделить live listening state от memorization state.
- Не записывать memorization в `AudioPlaybackStore` и remote position.
- Сохранять listening snapshot перед contextual playback.
- При выходе из Memorization остановить его и восстановить listening на паузе.
- Проверить Android/iOS Media Session и при необходимости использовать второй lazy player.

Проверки: fake engine, race conditions, stale requests, route disposal, interruption,
background/foreground, process restart, MediaItem ownership и snapshot isolation.

### 4. Flutter UI

- Заменить ручные `.where(timingsAvailable)` на role-aware repository.
- Использовать отдельные selection controls для Audio, Mushaf и Memorization.
- Не показывать untimed варианты в Mushaf/Memorization.
- Не показывать memorization playback в global mini-player.
- При уходе из Memorization остановить contextual playback.
- Сохранить unrelated plan/prayer UI изменения отдельно.

Проверки: Audio/Mushaf/Reader/Ayah Action Sheet/Memorization widget tests.

### 5. Cross-client contract

- Обновить TypeScript API models для additive DTO.
- Проверить, что web global player и MemorizationAudioLoop не смешивают preferences.
- Сохранить старые публичные endpoints во время миграции.
- Запустить web lint, typecheck, build и audio/memorization E2E smoke.

### 6. Platform verification

Android:

- emulator с `10.0.2.2`;
- физическое устройство с `adb reverse` и `127.0.0.1`;
- notification, lock screen, headset, Bluetooth, phone interruption;
- process kill/relaunch и восстановление Listening;
- отсутствие Memorization metadata в global widget.

iOS:

- iPhone Simulator и реальный iPhone;
- background audio, lock screen, interruption, route changes;
- suspend/resume и cold start;
- одинаковое поведение с Android при общей Dart-логике.

### 7. Full verification and release

```bash
make backend-check
make backend-test
make mobile-check
make mobile-android-production
make mobile-ios-config-check
make mobile-ios-production
```

Для изменённого общего API дополнительно запускаются web contract/E2E проверки и
существующие audio capacity/media contract проверки.

Release order:

1. additive backend contract;
2. backend validation and source data;
3. Flutter client with old/new DTO compatibility;
4. Android/iOS verification;
5. staged rollout;
6. только после подтверждения — production release.

Rollback сохраняет старые immutable audio versions, старые preference fallback и предыдущие
мобильные сборки. Удаление данных, очистка build/cache или destructive reset не входят в
обычный rollout.

## Definition of Done

- Listening, Mushaf и Memorization имеют независимые preferences.
- Untimed variant доступен только в разрешённых сценариях.
- Выбор чтеца A/B/C не меняет соседние каналы.
- Memorization не попадает в global widget и не перезаписывает Listening snapshot.
- Выход из Memorization останавливает его и восстанавливает Listening на паузе.
- Backend отклоняет неподдерживаемые ranges и неправильные Quran editions.
- Backend/OpenAPI/Flutter/Web checks зелёные.
- Android и iOS проходят platform smoke.
- Unrelated plan/prayer changes сохранены.
- Документация и release evidence обновлены.
