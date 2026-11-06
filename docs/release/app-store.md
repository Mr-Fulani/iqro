# Выпуск iOS-приложения в App Store

Пошаговая инструкция для владельца: что сделать один раз, как собрать сборку без Xcode на Mac,
как пройти TestFlight и что отвечать в App Store Connect. Тексты страницы приложения —
в [app-store-listing.md](app-store-listing.md). Android — в [google-play.md](google-play.md).

Состояние на 06.11.2026 (по коду `main` `40817807` и CI):

- iOS ни разу не собирался с подписью и не запускался на iPhone или iPad. CI (`.github/workflows/mobile.yml`,
  задача `ios`) на каждом PR собирает релизную сборку **без подписи** на `macos-15` с Xcode 26.3
  и гоняет нативные тесты `RunnerTests` в симуляторе; на `main` зелёный;
- аккаунта Apple Developer нет, приложения в App Store Connect нет;
- bundle ID `forum.iqro.app`, виджеты — `forum.iqro.app.PrayerTimesHomeWidget`, App Group
  `group.forum.iqro.app`; iOS/iPadOS 15+, iPhone и iPad;
- версия берётся из `pubspec.yaml` (`1.0.5+6` → «1.0.5», сборка 6), у виджета та же
  (это проверяет нативный тест);
- в проекте Xcode не задана команда (`DEVELOPMENT_TEAM`): без Team ID подписать сборку нельзя;
- файл связи с сайтом `https://iqro.forum/.well-known/apple-app-site-association` отдаётся,
  но пустой (`"details":[]`): на проде не задан Team ID.

## Что мешает выпуску

| # | Что | Кто | Статус |
|---|---|---|---|
| 1 | Apple Developer Program, 99 $ в год (раздел 1) | владелец, платно — только по его решению | не сделано |
| 2 | iPhone (и желательно iPad) с приложением TestFlight для проверки | владелец, тестировщики | неизвестно, есть ли iPhone у владельца |
| 3 | Bundle ID, App Group, Associated Domains на портале Apple (раздел 2) | владелец | не сделано |
| 4 | Приложение в App Store Connect (раздел 3) | владелец | не сделано |
| 5 | Ключ App Store Connect API и секреты в GitHub (разделы 2 и 4) | владелец вводит сам | не сделано |
| 6 | Workflow подписи и загрузки в TestFlight (раздел 4) | Claude, после согласования | не сделано |
| 7 | Строка разрешения на сохранение в «Фото» (раздел 9, правка 1) | Claude, после согласования | не сделано |
| 8 | Team ID на проде для Universal Links: `APPLE_APP_LINK_APPLICATION_IDENTIFIERS` | основная сессия, с «да» владельца | не сделано |
| 9 | Проверка на iPhone и iPad по [tech-debt 1.4](../tech-debt.md) | владелец и тестировщики через TestFlight | не сделано |
| 10 | Скриншоты iPhone 6,9″ и iPad 13″ на 4 языках (раздел 7) | Claude делает, владелец утверждает | не сделано |
| 11 | Анкеты App Store Connect: App Privacy, возраст, права, страны (раздел 6) | владелец по этому документу | не сделано |
| 12 | Статус «трейдер» в ЕС (DSA) и почтовый адрес, если трейдер | владелец | не решено |
| 13 | Отчёты о падениях (Sentry) в релизной сборке | владелец | не решено, как и для Android |

Для **внутреннего** TestFlight достаточно пунктов 1–7. Пункты 10–12 нужны только для
отправки на проверку App Store.

## Что уже готово в коде

| Что | Состояние |
|---|---|
| Значки | полный набор `AppIcon`, значок 1024×1024 без прозрачности (печать IQRO) |
| Заставка | `LaunchScreen.storyboard`: печать на бежевом фоне |
| Местоположение | `NSLocationWhenInUseUsageDescription` на 4 языках (`*.lproj/InfoPlist.strings`); «Всегда» не запрашивается, `geolocator` собран с `BYPASS_PERMISSION_LOCATION_ALWAYS` |
| Уведомления | разрешение запрашивается кодом, строка в Info.plist не нужна; учтён предел iOS в 64 запланированных уведомления (горизонт 8 дней) |
| Фоновая работа | `UIBackgroundModes`: `audio` (чтение Корана с выключенным экраном), `fetch` + `BGTaskSchedulerPermittedIdentifiers` для обслуживания кэша |
| Шифрование | `ITSAppUsesNonExemptEncryption = false`: только HTTPS и Keychain, вопросы об экспорте при каждой сборке не появятся |
| Сеть | в релизе исключений ATS нет; `NSAllowsArbitraryLoads` только в `Info-Debug.plist` |
| Privacy manifests | у приложения и у виджета (`PrivacyInfo.xcprivacy`); у пакетов из списка Apple свои манифесты есть. Без манифеста `audio_service`, `audio_session`, `just_audio`, `home_widget` и Flutter-обёртки Firebase: их нет в списке Apple, нативные Firebase-pods несут свои. Окончательно проверит App Store Connect при первой загрузке: недостающее придёт письмом ITMS-91053/91061 |
| Виджеты | WidgetKit: время намаза и план чтения с ростом пальмы, оба `systemMedium`; App Group одинаковый в обоих entitlements и в Dart; Swift компилируется в CI, но на устройстве не запускался |
| Deep links | схема `iqro://`, `FlutterDeepLinkingEnabled`, `applinks:iqro.forum` в entitlements; на сайте маршрут готов (пути `/dua/*` и `/salah`), не хватает только Team ID на проде |
| Firebase | параметры iOS берутся из `config/firebase.json` (`FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY`), `GoogleService-Info.plist` не нужен; сбор выключен до согласия; рекламного идентификатора нет (`$FirebaseAnalyticsWithoutAdIdSupport`), окно App Tracking Transparency не нужно |
| Вход через Google | на iOS выключен кодом (`google_sign_in_gateway.dart` показывает кнопку только на Android); на iOS — вход по коду из письма. См. раздел 8 |
| Sentry | пакет `sentry` (чистый Dart) без DSN — выключен; нативные сбои iOS не ловит |
| Звуки азана | `adhan_makkah.caf` 13,8 с и `adhan_madinah.caf` 20,4 с — короче предела iOS в 30 с, входят в ресурсы `Runner`; на iPhone не звучали |
| Удаление аккаунта | в приложении есть (требование 5.1.1(v)) |
| Пожертвования | сбор средств в приложении не показывается, только на сайте (требование 3.2.2) |

Найдено при аудите: **нет `NSPhotoLibraryAddUsageDescription`**. Картинка аята или ду'а уходит
в системное меню «Поделиться», там есть «Сохранить изображение», и без этой строки iOS
закрывает приложение. Исправление — правка 1 в разделе 9.

## 1. Аккаунт Apple Developer

1. Apple ID с двухфакторной защитой (лучше тот же `fulani.dev@gmail.com`, что в Google Play).
2. Вступить в Apple Developer Program: https://developer.apple.com/programs/enroll/ — проще всего
   из приложения **Apple Developer** на iPhone или iPad (там же оплата). Взнос **99 $ в год**,
   продлевается автоматически; без продления приложение пропадает из App Store.
3. Тип аккаунта:
   - **Личный (Individual)** — быстрее, в App Store продавцом будет имя владельца
     латиницей, как в документе;
   - **Организация** — нужен номер D-U-N-S (бесплатный, ждать до 2 недель), юрлицо и сайт.
     Для проекта без юрлица не подходит.

   Рекомендация — личный.
4. Проверка личности занимает от часов до нескольких дней. Соглашение программы владелец
   принимает сам. Для бесплатного приложения договор о платных приложениях, налоги и банк
   не нужны.
5. После одобрения: https://developer.apple.com/account → Membership details → **Team ID**
   (10 знаков). Он не секретный: его можно прислать в чат, он нужен для CI и Universal Links.

## 2. Идентификаторы и ключ API

На https://developer.apple.com/account/resources:

1. **Identifiers → App Groups → +**: `group.forum.iqro.app`, описание «IQRO widgets».
2. **Identifiers → App IDs → +** (тип App):
   - `forum.iqro.app`, описание «IQRO». Возможности (Capabilities): **App Groups** (выбрать
     `group.forum.iqro.app`) и **Associated Domains**. Push Notifications и Sign in with Apple
     не включать;
   - `forum.iqro.app.PrayerTimesHomeWidget`, описание «IQRO widgets». Возможность: **App Groups**
     (тот же `group.forum.iqro.app`).
3. Сертификаты и профили вручную не создаются: при сборке в CI Xcode сам получает облачный
   сертификат распространения и профили по ключу API (автоматическая подпись). Если это не
   сработает, запасной путь в разделе 4.

**Ключ App Store Connect API** (https://appstoreconnect.apple.com → Users and Access →
Integrations → App Store Connect API):

1. При первом входе Account Holder нажимает «Request Access» и принимает условия (делает владелец).
2. **Team Keys → +**: имя `IQRO CI`, роль **Admin**. Роль Admin нужна, чтобы CI сам создавал
   облачный сертификат и профили. Ключ даёт широкий доступ, поэтому хранится только в секретах
   GitHub.
3. Скачать файл `AuthKey_<KEY_ID>.p8` — **скачивается один раз**. Записать **Key ID** и
   **Issuer ID** (вверху страницы).
4. Копия `.p8` — в заблокированную заметку («IQRO ключ App Store Connect»), как ключ загрузки Play.
   Ни в git, ни в чат файл не попадает.

## 3. Приложение в App Store Connect

https://appstoreconnect.apple.com → Apps → **+ → New App**:

| Поле | Значение |
|---|---|
| Platforms | iOS |
| Name | `IQRO — Коран, аудио и намаз` (имя должно быть свободно во всём App Store; если занято — `IQRO: Коран, аудио и намаз`) |
| Primary Language | Russian |
| Bundle ID | `forum.iqro.app` |
| SKU | `iqro-ios` |
| User Access | Full Access |

Затем разделы из раздела 6: App Privacy, Age Rating, Pricing and Availability, App Information.

## 4. Сборка и загрузка без Xcode на Mac

Xcode на Mac ставить не нужно. Сборка, подпись и загрузка выполняются в GitHub Actions на
`macos-15` — там уже есть Xcode 26.3, которым собирается текущий CI. Репозиторий публичный,
минуты macOS бесплатны. Ниже — план (правка 2 в разделе 9), кода ещё нет.

Новый workflow `.github/workflows/ios-release.yml`, запуск только вручную (Actions →
iOS release → Run workflow) из `main`:

1. checkout, Ruby и CocoaPods из `Gemfile.lock`, Flutter 3.41.4, `flutter pub get --enforce-lockfile`,
   `pod install --deployment` — как в задаче `ios` сегодня;
2. `flutter build ios --release --config-only` с теми же `--dart-define`, что у Android:
   `APP_ENV=production`, `API_BASE_URL=https://iqro.forum`, `--dart-define-from-file=config/firebase.json`,
   а при решении владельца — `SENTRY_DSN`;
3. ключ `.p8` из секрета записывается во временный файл раннера и удаляется в конце;
4. `xcodebuild archive` с `DEVELOPMENT_TEAM=<Team ID>`, `-allowProvisioningUpdates` и ключом API
   (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`);
5. `xcodebuild -exportArchive` с `ios/ExportOptions.plist` (`method = app-store-connect`,
   `destination = upload`): сборка сразу уходит в App Store Connect;
6. архив `.xcarchive` с dSYM сохраняется артефактом запуска (нужен Sentry, если его включат).

Номер сборки берётся из `pubspec.yaml`; поле запуска `build_number` позволяет поднять его, если
App Store Connect уже видел такой номер. Apple требует, чтобы номер сборки рос внутри одной
версии. Номера iOS и Android независимы, но проще держать их одинаковыми.

**Секреты GitHub** (Settings → Secrets and variables → Actions). Значения вводит только владелец:

| Имя | Что | Тип |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID ключа API | secret |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID | secret |
| `APP_STORE_CONNECT_API_KEY_P8` | содержимое файла `AuthKey_<KEY_ID>.p8` целиком | secret |
| `APPLE_TEAM_ID` | Team ID | variable (не секрет) |
| `MOBILE_SENTRY_DSN` | DSN проекта `mobile`, только если включаем Sentry | secret |

Ключ можно положить из Терминала, не показывая его на экране (значение не печатается):

```bash
gh secret set APP_STORE_CONNECT_API_KEY_P8 --repo Mr-Fulani/iqro < ~/Downloads/AuthKey_XXXXXXXXXX.p8
```

Для ID ключа и Issuer ID: `gh secret set APP_STORE_CONNECT_API_KEY_ID --repo Mr-Fulani/iqro`
(значение вставить, когда команда попросит). Team ID:
`gh variable set APPLE_TEAM_ID --repo Mr-Fulani/iqro --body <TEAM_ID>`.

**Запасной путь — ручная подпись**, если облачная не заработает: владелец создаёт сертификат
Apple Distribution (CSR делается в «Связке ключей» на Mac, без Xcode) и два профиля App Store —
для приложения и для виджета. Тогда добавляются секреты `IOS_DISTRIBUTION_CERT_P12_BASE64`,
`IOS_DISTRIBUTION_CERT_PASSWORD`, `IOS_PROFILE_APP_BASE64`, `IOS_PROFILE_WIDGET_BASE64`,
а ключу API хватает роли App Manager.

fastlane не нужен: `xcodebuild` с ключом API делает то же самое без лишних зависимостей.

## 5. TestFlight

После загрузки App Store Connect обрабатывает сборку 10–30 минут, затем она видна в TestFlight.
Сборка живёт 90 дней.

1. **Внутреннее тестирование** — до 100 человек из команды App Store Connect (Users and Access),
   **без проверки Apple**. Владелец добавляет себя в группу, ставит приложение **TestFlight** на
   iPhone, принимает приглашение и устанавливает IQRO.
2. **Внешнее тестирование** — до 10 000 человек по почте или публичной ссылке. Первая сборка
   каждой версии проходит **Beta App Review** (обычно до суток). Нужно заполнить Test Information:
   - Beta App Description: «Приложение для чтения и изучения Корана: Мусхаф, чтецы, время
     намаза, курсы, ду'а. Работает без аккаунта.»;
   - Feedback Email: `fulani.dev@gmail.com`;
   - Beta App Review Information: контакт владельца, **Sign-in required — нет**;
   - Privacy Policy URL: `https://iqro.forum/ru/privacy`.
3. Публичную ссылку внешнего теста можно отправить в группу `iqro-testers` для тех, у кого iPhone.

Что проверить на устройстве — список [tech-debt 1.4](../tech-debt.md): виджеты после Иша, азан
в напоминаниях, кнопки плеера на экране блокировки после интро, Мусхаф, свайпы, Universal Links.
Плюс: «Поделиться» картинкой → «Сохранить изображение», вход по коду из письма, удаление
аккаунта, офлайн-режим, iPad в альбомной ориентации.

## 6. Ответы в App Store Connect

### App Information

| Поле | Значение |
|---|---|
| Subtitle и тексты | [app-store-listing.md](app-store-listing.md) |
| Category | Primary **Reference** (Справочники), Secondary **Education** (Образование) |
| Content Rights | «Contains, shows, or accesses third-party content» — **Yes**, «have the necessary rights» — **Yes** |
| Privacy Policy URL | `https://iqro.forum/ru/privacy` (на 4 языках: `/en/`, `/ar/`, `/tr/`) |
| Support URL | `https://iqro.forum/ru/contacts` |
| Marketing URL | `https://iqro.forum` |
| Copyright | `2026 Mr.Fulani (Iqro-Forum project)` |

### Цена и страны

Бесплатно. Все страны, **кроме материкового Китая**: там для новых приложений нужен номер ICP,
которого у проекта нет.

**ЕС (Digital Services Act).** Apple требует указать, является ли разработчик трейдером.
Трейдер публикует на странице приложения адрес, телефон и почту. Бесплатное приложение без
доходов обычно отмечают «не трейдер», и оно всё равно доступно в ЕС. Решает владелец.

### App Privacy

Общие ответы:

- Собираете ли данные: **Yes**.
- Tracking (передача рекламным сетям, брокерам данных): **No** ни для одного типа.
  Рекламы и IDFA нет.

Типы данных (сверено с `ios/Runner/PrivacyInfo.xcprivacy` и с ответами для Google Play):

| Тип Apple | Назначение | Связан с пользователем | Когда |
|---|---|---|---|
| Contact Info → Email Address | App Functionality | Yes | только при входе и в обращении в поддержку |
| Location → Precise Location | App Functionality | No | по разрешению: координаты уходят на `/prayer/calculate` для времени намаза |
| Location → Coarse Location | Analytics | No | только с согласия на статистику: город по IP в Firebase Analytics |
| Identifiers → User ID | App Functionality | Yes | всегда: серверный ID гостевой или полной учётной записи |
| Identifiers → Device ID | App Functionality, Analytics | Yes | всегда: ключ установки; с согласия — ID экземпляра Firebase |
| Usage Data → Product Interaction | Analytics | No | только с согласия: события «открыта сура», «включено аудио» и т. п. |
| User Content → Customer Support | App Functionality | Yes | при обращении |
| User Content → Other User Content | App Functionality | Yes | при входе: закладки, заметки, план, прогресс |
| Diagnostics → Other Diagnostic Data | App Functionality | Yes | версия приложения и iOS в обращении |
| Diagnostics → Crash Data, Performance Data | App Functionality | No | **только** если сборка с `SENTRY_DSN`; иначе не отмечать |

Не собираются: финансы, здоровье, контакты, фото и видео, аудио, история браузера и поиска,
покупки, чувствительные данные.

### Возрастной рейтинг

Анкета (новая система Apple 4+/9+/13+/16+/18+): на все вопросы о насилии, страхе, азартных играх,
алкоголе, сексуальном контенте, нецензурной лексике, медицине — **None**. Unrestricted Web Access
— **No** (встроенный WebView показывает только 3D-сцены нашего сайта). User-Generated Content,
Messaging — **No** (заметки личные, обращения видит только поддержка). Advertising — **No**.
Ожидаемый рейтинг **4+**.

### Экспортный контроль

`ITSAppUsesNonExemptEncryption = false` уже в Info.plist: App Store Connect не будет спрашивать
о шифровании при каждой сборке. Если спросит при первой версии: используется только
шифрование ОС (HTTPS, Keychain) — **освобождено**, документы не нужны.

### App Review Information

- Sign-in required: **нет**. Всё работает без входа (гостевой режим), вход нужен только для
  синхронизации между устройствами.
- Notes (по-английски):

  > IQRO works without an account. Sign-in by an emailed code is optional and only syncs
  > bookmarks, notes and reading progress between devices. Background audio: the user starts
  > a Quran recitation and keeps listening with the screen locked; lock-screen controls are
  > shown. Location (when in use) is used only to calculate local prayer times; a city can be
  > chosen manually instead. Home-screen widgets: prayer times and the daily reading plan.

- Если Apple всё же попросит демо-аккаунт: вход только по коду из письма, проверяющий код не
  получит. Тогда нужна правка 6 из раздела 9.

## 7. Скриншоты

| Устройство | Размер, портрет | Нужно |
|---|---|---|
| iPhone 6,9″ | 1320×2868 (или 1290×2796) | обязательно, 1–10 на язык |
| iPhone 6,5″ | 1284×2778 (или 1242×2688) | необязательно: App Store уменьшает 6,9″ сам |
| iPad 13″ | 2064×2752 (или 2048×2732) | **обязательно**: приложение поддерживает iPad |

Значок для страницы берётся из сборки (1024×1024 в `AppIcon`), отдельно не загружается.

Без Xcode на Mac снимки делаются в CI: интеграционный тест открывает нужные экраны в
симуляторах iPhone 17 Pro Max и iPad Pro 13″ на 4 языках и сохраняет снимки артефактом
(правка 5 в разделе 9). Набор экранов как для Google Play: Мусхаф с подсветкой, плеер, время
намаза, план с пальмой, курс намаза, ду'а. Снимки с текстами, а не только интерфейс —
по желанию владельца.

## 8. Вход через Google и правило 4.8

Правило App Store 4.8: если приложение даёт вход через сторонний сервис (Google), оно должно
предложить и равноценный вход, который собирает только имя и почту, позволяет скрыть почту
и не отслеживает пользователя. На практике это «Войти с Apple». Вход по коду из письма это
требование не закрывает: почту скрыть нельзя.

Сейчас на iOS кнопки Google нет (код показывает её только на Android), а вход по коду из письма —
собственная система аккаунтов IQRO. Поэтому **правило 4.8 к первой версии не применяется,
«Войти с Apple» не нужен**.

Если позже включать Google на iOS, понадобится сразу три вещи: iOS-клиент OAuth в Google Cloud,
`GIDClientID` и URL-схема в Info.plist, и «Войти с Apple» на iOS (а для паритета — и на сайте
и Android) с проверкой токена Apple на бэкенде. Оценка — 2–4 дня. Пока это расхождение
iOS с Android и сайтом.

## 9. Правки в коде до первой сборки TestFlight

**Ждут согласования владельца, код ещё не менялся.**

| # | Правка | Зачем | Нужна для | Оценка |
|---|---|---|---|---|
| 1 | `NSPhotoLibraryAddUsageDescription` в `Info.plist`, `Info-Debug.plist` и 4 `InfoPlist.strings` + проверка в `RunnerTests` | иначе «Сохранить изображение» из «Поделиться» закрывает приложение | TestFlight | 30 мин |
| 2 | `.github/workflows/ios-release.yml` и `ios/ExportOptions.plist` (раздел 4), Team ID из переменной `APPLE_TEAM_ID`; README приложения | подпись и загрузка в TestFlight без Xcode на Mac | TestFlight | 0,5–1 день вместе с 1–3 пробными запусками |
| 3 | `NSPrivacyCollectedDataTypeCoarseLocation` (Analytics) в `PrivacyInfo.xcprivacy` | манифест совпадёт с ответами App Privacy | желательно | 15 мин |
| 4 | Аудиосессия после интро (аудит 4.7, tech-debt 1.4) | кнопки плеера на экране блокировки | только если ошибка видна в TestFlight | 1–2 ч |
| 5 | Снимки экрана в CI на симуляторах iPhone 6,9″ и iPad 13″, 4 языка | страница App Store | App Store, не TestFlight | ~1 день |
| 6 | Вход для проверяющего Apple (почта и постоянный код только для одного адреса из env) | если Apple попросит демо-аккаунт | по запросу Apple | 0,5 дня, бэкенд |

Не правка кода, а настройка сервера, тоже до проверки Universal Links: в `services/backend/.env.production`
на проде `APPLE_APP_LINK_APPLICATION_IDENTIFIERS=<TEAM_ID>.forum.iqro.app`, затем перезапуск
контейнера `web` (значение читается при запросе, пересобирать образ не нужно). Проверка:
`curl -s https://iqro.forum/.well-known/apple-app-site-association` — в `details` появится `appID`.
Apple забирает файл через свой CDN, обновление доходит до суток.

Сейчас не нужны: «Войти с Apple», Google на iOS, замена `sentry` на `sentry_flutter`
(tech-debt 1.1), push-уведомления.

Минимум до первой сборки во внутреннем TestFlight: правки 1 и 2 плюс разделы 1–2 от владельца.

## 10. Перед каждым следующим выпуском

1. Поднять номер сборки в `pubspec.yaml` (общий с Android).
2. Запустить workflow iOS release из `main`, дождаться сборки в TestFlight.
3. Проверить на iPhone во внутреннем тестировании.
4. В App Store Connect: новая версия → выбрать сборку → «What's New» на 4 языках → отправить на
   проверку. Выпуск — вручную после одобрения или поэтапно (Phased Release, 7 дней).
