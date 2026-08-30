# IQRO Mobile

Нативный Android-клиент IQRO на Flutter. Клиент использует действующие API-контракты
платформы, хранит пользовательские изменения локально и синхронизирует их после
восстановления сети.

## Быстрый запуск на Android

Требуются Flutter 3.41+, Android SDK и устройство с включённой USB-отладкой либо
Android Emulator.

```bash
cd clients/iqro_mobile
flutter pub get
flutter doctor
flutter devices
flutter run \
  --dart-define=API_BASE_URL=https://staging.iqro.forum \
  --dart-define=APP_ENV=staging
```

При первом запуске приложение создаёт безопасную гостевую сессию. Коран, Мусхаф,
чтецы, аудио, ду’а, время намаза и функция «Поделиться» загружаются со staging API.

## Тестовый APK

```bash
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://staging.iqro.forum \
  --dart-define=APP_ENV=staging

adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

- application ID: `forum.iqro.app`;
- минимальная версия Android определяется поддерживаемой версией Flutter;
- staging используется по умолчанию, но окружение всегда лучше передавать явно;
- `APP_DOWNLOAD_URL` задаёт встроенную запасную ссылку для функции «Поделиться».

Debug APK подписывается стандартным отладочным ключом. Release-сборка не использует
debug-подпись: CI или локальный защищённый контур должен передать `android/key.properties`
и keystore. Секреты не должны попадать в Git.

## Проверки

```bash
flutter gen-l10n
flutter analyze
flutter test
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://staging.iqro.forum \
  --dart-define=APP_ENV=staging
```

## Архитектура

- `lib/app` — композиция зависимостей, маршрутизация и глобальные providers;
- `lib/core` — API, авторизация, SQLite, синхронизация, аудио и дизайн-система;
- `lib/features` — независимые вертикальные продуктовые модули;
- `lib/l10n` — RU/EN/AR/TR, включая полноценный RTL;
- `test` — unit-тесты модели сессии, настроек и API-моделей.

Детальные границы слоёв, offline-модель и порядок расширения описаны в
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Безопасность и приватность

- access/refresh token, installation ID и installation credential хранятся в Android
  Keystore-backed secure storage;
- HTTP cleartext запрещён;
- резервное копирование данных приложения отключено;
- координаты используются только для запроса расчёта времени намаза и не добавляются
  в аналитику;
- технические UUID пользователя и устройства не показываются в пользовательском UI.

## Ограничения тестовой версии

Store-signing, Play Console, push-доставка и production endpoint намеренно не включены.
Книги и квизы показаны как будущие разделы. Тексты переводов/тафсира не подменяются
mock-данными: интерфейс сообщает, когда утверждённый источник ещё не подключён.
