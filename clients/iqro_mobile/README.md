# IQRO Mobile

Нативный мобильный клиент IQRO на Flutter для Android, iPhone и iPad. Все платформы
используют один Dart-код и действующие API-контракты платформы, хранят пользовательские
изменения локально и синхронизируют их после восстановления сети.

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
- staging используется по умолчанию только в debug-режиме;
- release-сборка без явных `APP_ENV` и `API_BASE_URL` намеренно не завершит
  инициализацию, а production принимает только `https://iqro.forum`;
- `APP_DOWNLOAD_URL` задаёт встроенную запасную ссылку для функции «Поделиться».

Debug APK подписывается стандартным отладочным ключом. Release-сборка не использует
debug-подпись: CI или локальный защищённый контур должен передать `android/key.properties`
и keystore. Секреты не должны попадать в Git.

## iPhone и iPad

Требуются полный Xcode 26+, CocoaPods и Apple Developer signing только для установки
на физическое устройство или публикации. Проверить общую конфигурацию и собрать
неподписанный staging target можно так:

```bash
make mobile-ios-config-check
make mobile-ios-staging
```

iOS target имеет bundle ID `forum.iqro.app`, поддерживает iOS/iPadOS 14+, UIScene,
фоновые аудио и обслуживание, локальные уведомления и локализованные permission-тексты
RU/EN/AR/TR. Геопозиция запрашивается только во время использования приложения для
расчёта времени намаза; фоновый location-доступ не включён.

Фирменные app icon и launch mark для обеих платформ воспроизводимо экспортируются из
одной геометрии командой `cd clients/iqro_mobile && swift tool/generate_app_icons.swift`.

## Окружения без flavors

Отдельные flavors не нужны: один и тот же код компилируется с явной конфигурацией.

```bash
# Тестовый сервер
make mobile-android-staging

# Production AAB; без keystore получится только неподписанный compile-check
make mobile-android-production

# Production iOS compile-check; без signing и загрузки в App Store Connect
make mobile-ios-production
```

`APP_ENV=staging` принимает только `https://staging.iqro.forum`, а
`APP_ENV=production` — только `https://iqro.forum`. Это исключает случайный релиз,
направленный не в то окружение.

## Проверки

```bash
make mobile-check
make mobile-android-staging
```

Mobile CI закреплён на Flutter 3.41.4, проверяет lock-файлы, форматирование,
сгенерированные локализации, анализ, тесты, staging APK, production AAB и production
iPhone/iPad compile на Xcode 26.3. Gradle wrapper хранится в Git, а JAR и дистрибутив
проверяются официальными SHA-256.

## Архитектура

- `lib/app` — композиция зависимостей, маршрутизация и глобальные providers;
- `lib/core` — API, авторизация, SQLite, синхронизация, аудио и дизайн-система;
- `lib/features` — независимые вертикальные продуктовые модули;
- `lib/l10n` — RU/EN/AR/TR, включая полноценный RTL;
- `test` — unit-тесты модели сессии, настроек и API-моделей.

Детальные границы слоёв, offline-модель и порядок расширения описаны в
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Безопасность и приватность

- access/refresh token, installation ID и installation credential хранятся в
  Keystore/Keychain-backed secure storage;
- HTTP cleartext запрещён;
- API не следует HTTP redirect и принимает только соответствующий окружению HTTPS origin;
- резервное копирование данных приложения отключено;
- координаты используются только для запроса расчёта времени намаза и не добавляются
  в аналитику;
- технические UUID пользователя и устройства не показываются в пользовательском UI.

## Ограничения тестовой версии

Store-signing, Play Console, App Store Connect и push-доставка намеренно не включены.
Production endpoint поддержан через compile-time конфигурацию, но публикация требует
Android upload keystore либо Apple certificates/provisioning profiles. Книги и квизы
показаны как будущие разделы. Тексты переводов/тафсира не подменяются mock-данными:
интерфейс сообщает, когда утверждённый источник ещё не подключён.

Подробный порядок подписанной публикации описан в
[`docs/RELEASE.md`](docs/RELEASE.md).
