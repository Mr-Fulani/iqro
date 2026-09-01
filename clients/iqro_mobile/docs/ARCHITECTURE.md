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
- `AudioController` владеет единственным player instance. Смена чтеца останавливает
  старый источник; MediaSession продолжает работать в фоне и на lock screen.

### Features

Каждый модуль содержит UI, repository и модели только своей предметной области. Общение
между модулями идёт через providers и доменные ID, а не через импорт экранов. Новый модуль
добавляется в четыре шага: repository → provider/controller → route → screen.

## Offline и синхронизация

| Данные | Чтение offline | Запись offline | Синхронизация |
|---|---|---|---|
| Каталог сур и аяты | cache-first/fallback | — | ETag/обновление из API |
| Полный Мусхаф | активный проверенный package | resumable download | versioned manifest + SHA-256 |
| Чтецы и аудиометаданные | cache fallback | выбранный чтец локально | API при доступной сети |
| Позиция чтения и закладки | SQLite | SQLite + outbox | push/pull с revision |
| Ду’а | локализованный cache fallback | избранное + outbox | идемпотентный PUT/retry |
| План и заучивание | SQLite | SQLite | готовая граница repository для API-sync |
| Share/referral events | встроенный fallback | outbox | идемпотентный event API |

`MushafOfflineRepository` устанавливает новую версию в отдельный каталог, возобновляет
`.part`-файлы через HTTP Range и проверяет размер, WebP signature и SHA-256. Метаданные
страниц и переключение `is_active` применяются одной SQLite-транзакцией только после
полной проверки 604 страниц; до этого читалка продолжает использовать прежний пакет.
Обычный on-demand cache остаётся fallback для пользователей без полного download.

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
release keystore через секреты CI и собираться из конкретного commit SHA.

## Следующие безопасные расширения

1. Выделить `core/network`, `core/storage` и дизайн-систему в workspace packages, когда
   появится второй Flutter target или независимые команды.
2. Добавить WorkManager для фонового outbox retry с экспоненциальной задержкой.
3. Подключить серверные reminder profiles и локальный Android scheduler за отдельным
   `NotificationGateway`.
4. Добавить управляемые offline-download packages для аудио на существующем manifest API.
5. Добавить integration tests на Android emulator и release pipeline с SBOM/signing.
