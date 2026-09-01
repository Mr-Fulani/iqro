# Выпуск IQRO Mobile

## Инварианты

- Сборка всегда привязана к конкретному Git commit и версии `pubspec.yaml`.
- Staging и production используют один код без flavors, но разные обязательные
  compile-time значения.
- Keystore, пароли и `android/key.properties` не хранятся в Git и не копируются на
  backend-сервер.
- Перед публикацией обязательны `make mobile-check` и production release compile.

## Staging APK

```bash
make mobile-check
make mobile-android-staging
```

Результат: `clients/iqro_mobile/build/app/outputs/flutter-apk/app-debug.apk`.
Debug APK предназначен только для ручной проверки на устройстве и обращается к
`https://staging.iqro.forum`.

## Android signing

Upload keystore хранится вне репозитория. Локальный файл
`clients/iqro_mobile/android/key.properties` содержит четыре ссылки на секреты:

```properties
storeFile=/absolute/protected/path/iqro-upload.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Gradle прерывает конфигурацию, если файл существует, но поле пустое или keystore не
найден. Значения нельзя печатать в CI log. Для Google Play предпочтителен Play App
Signing: IQRO хранит upload key, а ключ подписи приложения защищает Google.

## Production AAB

```bash
make mobile-check
make mobile-android-production
```

Результат: `clients/iqro_mobile/build/app/outputs/bundle/release/app-release.aab`.
Команда явно закрепляет `APP_ENV=production`, API `https://iqro.forum` и публичную
страницу загрузки. Release без этих значений не получает рабочую конфигурацию.

Перед загрузкой в Play Console:

1. убедиться, что Git-дерево чистое и записать commit SHA;
2. увеличить `version`/build number в `pubspec.yaml`;
3. пройти сценарии первого запуска, чтения, аудио, offline, аккаунта и напоминаний на
   staging-сборке;
4. выполнить production compile и сохранить mapping/symbol artifacts рядом с релизом;
5. проверить подпись AAB в защищённом release-контуре;
6. выпустить сначала во internal testing, затем staged rollout;
7. откатывать публикацию через Play Console или новым build number — уже опубликованный
   version code повторно использовать нельзя.

## CI

`.github/workflows/mobile.yml` использует Flutter 3.41.4 и Java 17. Он проверяет:

- неизменяемый `pubspec.lock`;
- Dart format и сгенерированные RU/EN/AR/TR локализации;
- `flutter analyze` и все unit-тесты;
- Gradle wrapper JAR и distribution SHA-256;
- arm64 staging APK;
- production release AAB compile без доступа к release secrets.

Подписанная публикация должна быть отдельным protected workflow с ручным approval.
