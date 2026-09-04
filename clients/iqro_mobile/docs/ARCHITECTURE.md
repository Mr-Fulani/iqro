# Архитектура IQRO Mobile

## Цели

Клиент построен как один Flutter application package с независимыми feature-модулями.
Это сохраняет простую сборку на старте и позволяет позже выделять модули в отдельные
packages без переписывания экранов или сетевого слоя.

## Поток данных

```text
Screen → Riverpod controller/provider → Feature repository
                                      ↙                  ↘
                              SQLite/cache/outbox      API client
                                      ↘                  ↙
                                      Sync service
```

Экран не знает URL API, формат secure storage или структуру таблиц. Repository переводит
ответы API в доменные модели, сохраняет разрешённый кэш и ставит пользовательские
изменения в outbox. Поэтому новый транспорт, background worker или отдельный package
можно подключить за существующим интерфейсом repository.

## Слои

### App

`AppDependencies` создаёт все долгоживущие зависимости один раз. Riverpod overrides
позволяют заменять их fake-реализациями в тестах. `GoRouter` хранит карту экранов, а
`AppShell` отвечает за пять основных вкладок и постоянный мини-плеер.

### Core

- `AuthRepository` создаёт стабильную установочную identity, сериализует обновление
  токенов и хранит сессию одной атомарной записью в secure storage.
- `ApiClient` добавляет язык и bearer token, выполняет один refresh и повторяет исходный
  запрос только после успешного обновления.
- `LocalDatabase` владеет версией SQLite schema, кэшем, позициями чтения и outbox.
- `SyncService` отправляет идемпотентные операции, затем применяет server cursor pull;
  конфликт не показывается пользователю техническим кодом.
- `BackgroundMaintenanceService` одним системным заданием отправляет outbox, сверяет
  позицию аудио и автономно продлевает локальные напоминания; сеть для запуска задания
  не обязательна.
- `AudioPlaybackSyncService` использует server revision и timestamp клиента, поэтому
  изменения на двух устройствах разрешаются детерминированно, а снятый с публикации
  трек никогда не восстанавливается в плеер.
- `AudioController` владеет единственным player instance. Экран аудио одним запросом получает
  опубликованный каталог декламаций и фильтрует персон по виду чтения; исходный фильтр —
  `murattal`. Тап по карточке чтеца разрешает вариант выбранного вида и текущую суру, затем
  атомарно заменяет источник и открывает полный плеер; прежний поток не прерывается во время
  сетевого поиска новой дорожки. В полном плеере повторный выбор вида/чтеца сохраняет суру
  и play/pause; позиция пересчитывается по относительному прогрессу текущего аята только при
  совместимых таймкодах, иначе новая дорожка начинается с начала.
  MediaSession продолжает работать в фоне и на lock screen.

### Features

Каждый модуль содержит UI, repository и модели только своей предметной области. Общение
между модулями идёт через providers и доменные ID, а не через импорт экранов. Новый модуль
добавляется в четыре шага: repository → provider/controller → route → screen.

## Offline и синхронизация

| Данные | Чтение offline | Запись offline | Синхронизация |
|---|---|---|---|
| Каталог сур и аяты | cache-first/fallback | — | ETag/обновление из API |
| Полный Мусхаф | активный проверенный package | resumable download | versioned manifest + SHA-256 |
| Чтецы и аудиометаданные | cache fallback + проверенный audio package | позиция и настройки плеера | versioned account position API |
| Позиция чтения и закладки | SQLite | SQLite + outbox | push/pull с revision |
| Ду’а | локализованный cache fallback | избранное + outbox | идемпотентный PUT/retry |
| План чтения | SQLite | SQLite | backend parity для goals/sessions/history ещё не подключён |
| Заучивание | cache fallback | API-команды с локальным fallback | versioned account API |
| Share/referral events | встроенный fallback | outbox | идемпотентный event API |

`MushafOfflineRepository` устанавливает новую версию в отдельный каталог, возобновляет
`.part`-файлы через HTTP Range и проверяет размер, WebP signature и SHA-256. Метаданные
страниц и переключение `is_active` применяются одной SQLite-транзакцией только после
полной проверки 604 страниц; до этого читалка продолжает использовать прежний пакет.
Обычный on-demand cache остаётся fallback для пользователей без полного download.
Навигация scan-Мусхафа загружает опубликованные backend-границы сур/аятов, джузов, хизбов
и руб аль-хизбов; выбор переводится в точную страницу и начальный аят без локальной таблицы.

`AudioOfflineRepository` применяет тот же принцип к 114 аудиодорожкам: Range-resume,
проверка формата, размера и SHA-256, затем атомарная активация. `NotificationGateway`
строит горизонт намазов локальным портом закреплённого движка Adhan, поэтому WorkManager
может продлевать расписание без сети.

## Apple platform

Один iOS target обслуживает iPhone и iPad (`TARGETED_DEVICE_FAMILY = 1,2`) с minimum
iOS/iPadOS 14. UIScene является единственным lifecycle. `AppDelegate` до завершения
launch регистрирует BGTaskScheduler handlers и plugin registrant для отдельного
background Flutter engine. Идентификатор `forum.iqro.app.periodic-maintenance-v1`
одинаков в Dart, `Info.plist` и native registration, поэтому outbox, playback sync и
горизонт напоминаний могут обслуживаться системным BGAppRefreshTask.

`UIBackgroundModes` ограничены `audio` и `fetch`. Location background mode и Always
permission отсутствуют: координаты запрашиваются только при открытом приложении для
локального расчёта времени намаза. Нативные dependency-версии фиксирует `Podfile.lock`,
а CocoaPods-конфигурации разделены для Debug/Profile/Release.

## Локализация и RTL

ARB-файлы являются единственным источником интерфейсных строк. Layout использует
`EdgeInsetsDirectional`, `AlignmentDirectional` и направление Flutter locale. Арабский
Quran-текст всегда получает RTL и отдельную типографику независимо от языка интерфейса.

## Конфигурация окружения

Конфигурация задаётся только compile-time переменными:

```text
API_BASE_URL      корень backend без /api/v1
APP_ENV           staging или production
APP_DOWNLOAD_URL  fallback URL для системного share sheet
```

В коде и Git нет API-ключей или серверных секретов. Production build должен получать
release keystore через секреты CI и собираться из конкретного commit SHA. В
release-режиме пустая конфигурация запрещена, а окружение жёстко связано с первым
доменом IQRO.

## Следующие безопасные расширения

1. Завершить связку Мусхаф ↔ аудио: дополнительные проверенные native-варианты Мусхафа и
   выбор разрешённого качества аудиодорожки.
2. Подключить мобильный План к backend goals/sessions/history и автоматическому зачёту
   реально прочитанных страниц.
3. Добавить расширенные настройки расчёта намаза и управление устройствами/приватностью.
4. Добавить profile/release performance evidence, Android device integration smoke-tests,
   подписанный Play Console pipeline и iPhone/iPad real-device matrix.
5. Вынести обезличенную crash/QoE telemetry за отдельный consent и privacy review.
6. Выделить `core/network`, `core/storage` и дизайн-систему в workspace packages только
   после появления независимых команд или второго Flutter-приложения.
