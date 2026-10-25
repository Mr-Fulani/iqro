# Статистика посещений и поиска

Сайт iqro.forum подключён к Google Analytics 4, Google Search Console, Яндекс Метрике и
Яндекс Вебмастеру, мобильное приложение — к тому же ресурсу GA4 через Firebase. Все ресурсы
принадлежат аккаунту fulani.dev@gmail.com (в Яндексе — Яндекс ID mr.fulani, запасная почта
fulani.dev@gmail.com).

| Сервис | Ресурс | Что там смотреть |
|---|---|---|
| Google Analytics 4 | аккаунт «Mr.Fulani», ресурс «IQRO» (p560666384), веб-поток `G-TKV2YGN4KZ`, потоки приложений «IQRO Android» и «IQRO iOS» | посетители, источники, страницы, экраны, события |
| Firebase | проект «IQRO» (`iqro-d9df7`), приложения Android и iOS `forum.iqro.app`, связан с ресурсом GA4 «IQRO» | DebugView, потоки приложений |
| Google Search Console | доменный ресурс `iqro.forum` (подтверждён TXT-записью в Cloudflare) | поисковые запросы Google, индексация, карты сайта |
| Яндекс Метрика | счётчик «IQRO» `113787874` | посетители, цели, Вебвизор, карта скроллинга |
| Яндекс Вебмастер | `https://iqro.forum` (подтверждён TXT-записью в Cloudflare) | поисковые запросы Яндекса, индексация |

Связки: Search Console ↔ GA4 (отчёты «Search Console» в GA), Метрика ↔ Вебмастер.
Google Signals и персонализация рекламы в GA выключены (религия — деликатная категория),
события хранятся 14 месяцев. В Вебвизоре выключена запись содержимого полей ввода.

## Как это работает на сайте

- ID счётчиков встраиваются при сборке образа web: `WEB_GA_MEASUREMENT_ID` и
  `WEB_YANDEX_METRIKA_ID` в `.env.production` (→ `NEXT_PUBLIC_GA_MEASUREMENT_ID`,
  `NEXT_PUBLIC_YANDEX_METRIKA_ID`). Пустые значения — ни баннера, ни счётчиков.
- Пока посетитель не нажал «Принять» в баннере (`components/AnalyticsConsent.tsx`), ничего не
  загружается и не отправляется. Выбор хранится в `localStorage` (`iqro_analytics_consent_v1`)
  и меняется на странице `/cookies`; отзыв удаляет cookies `_ga*`/`_ym*` и перезагружает страницу.
- После согласия скрипты `gtag.js` и `tag.js` грузятся после события `load`, в
  `requestIdleCallback`, поэтому не мешают первой отрисовке. Баннер `position: fixed` и
  появляется после загрузки страницы — макет не сдвигается.
- Домены счётчиков разрешены в CSP дважды: `services/web/next.config.mjs` и
  `ops/gateway/security-headers.conf` (шлюз заменяет CSP от Next). Совпадение проверяет
  `ops/gateway/test_config.py`. Список намеренно короткий (googletagmanager, yastatic.net,
  mc.yandex.ru, mc.yandex.com): хиты идут по `https:`, которое `connect-src` и `img-src` уже
  разрешают, а заголовок CSP уходит с каждым ответом — полный список доменов Яндекса добавлял
  ~1,3 КБ к каждому запросу и выводил страницы за бюджеты Lighthouse.
- `frame-ancestors 'none'` и `X-Frame-Options: DENY` не менялись: Вебвизор 2.0 воспроизводит
  записи без встраивания сайта во фрейм. Режим «карта кликов поверх сайта» поэтому недоступен.

## Как это работает в приложении

- Firebase Analytics, а не Яндекс: AppMetrica — отдельный от Метрики кабинет, а Firebase пишет
  в тот же ресурс GA4, что и сайт, поэтому сайт и приложение видны в одних отчётах (фильтр
  «Поток» или «Платформа»).
- ID Firebase лежат в `clients/iqro_mobile/config/firebase.json` (это не секреты: Google
  ограничивает ключи приложениями). Производственные сборки передают файл через
  `--dart-define-from-file` (`make mobile-android-production`, `make mobile-ios-production`,
  Mobile CI). Сборка без него — ни карточки согласия, ни Firebase.
- Пока пользователь не нажал «Принять» на карточке над нижним меню
  (`lib/features/settings/analytics_consent.dart`), Firebase даже не инициализируется. Выбор
  хранится на устройстве под тем же ключом, что на сайте (`iqro_analytics_consent_v1`), и
  меняется переключателем «Статистика использования» в настройках; отказ вызывает
  `setAnalyticsCollectionEnabled(false)` и `resetAnalyticsData()`.
- В `AndroidManifest.xml` и `Info.plist` сбор выключен по умолчанию, реклама запрещена
  (`firebase_analytics_collection_enabled`, `google_analytics_default_allow_ad_*`), разрешение
  `AD_ID` удалено, на iOS пакет без IDFA (`$FirebaseAnalyticsWithoutAdIdSupport`).
  `PrivacyInfo.xcprivacy` объявляет взаимодействие с продуктом и идентификатор устройства для
  аналитики, без отслеживания.
- Android-часть Firebase читает `google_app_id` из ресурсов при старте приложения, поэтому
  `android/app/build.gradle.kts` превращает те же значения из `--dart-define-from-file` в
  строковые ресурсы. Сервисы Google Play для статистики собраны Kotlin 2.4, поэтому Kotlin
  Gradle Plugin поднят с 2.2.20 до 2.3.21 (`kotlinOptions` → `compilerOptions`).
- Firebase требует iOS 15+, поэтому минимальная версия iOS поднята с 14 до 15. Версии
  `firebase_core`/`firebase_analytics` закреплены: более новые требуют Firebase iOS SDK,
  которого больше нет в CocoaPods. На iOS Firebase настраивается из Dart без
  `GoogleService-Info.plist`; живьём это ещё не проверено (нет Xcode и Apple-аккаунта).

## События

Одинаковые имена уходят в GA4 (`gtag('event', …)`) и в Метрику (`reachGoal`); приложение
отправляет те же имена и параметры в GA4 через Firebase (`lib/core/analytics/analytics.dart`).

| Событие | Когда | Параметры |
|---|---|---|
| `surah_open` | сура оставалась текущей в читалке 3 секунды (раз за визит на суру) | `surah` |
| `audio_play` | плеер реально заиграл (раз на запуск) | `kind` (surah/ayah/range), `surah`, `reciter` |
| `lesson_complete` | урок отмечен изученным (тематические курсы, таджвид, намаз) | `course`, `lesson` |
| `share` | «Поделиться» прошло или ссылка/текст скопированы | `content_type` (ayah/dua/course), `method` (native/copy_text/copy_link) |
| `login` | вход по коду из письма | `method` |

В приложении `surah_open` срабатывает и в текстовой читалке, и в мусхафе; `lesson_complete`
для намаза уходит с `course: salah`, как на сайте; `share` — только когда в системном меню
выбрали, куда отправить (`method: native`).

Просмотры страниц при переходах внутри сайта GA4 считает сам (улучшенная статистика по
history API); Метрике их отправляет `trackPageView()`.

В Метрике под эти события заведены цели типа «JavaScript-событие» с теми же идентификаторами.
В GA4 события появляются в отчётах через 24–48 часов после первого срабатывания; тогда в
«Администратор → События» их можно отметить ключевыми.

## Выкладка

1. В `.env.production` на сервере: `WEB_GA_MEASUREMENT_ID=G-TKV2YGN4KZ`,
   `WEB_YANDEX_METRIKA_ID=113787874`.
2. Обновить `LEGAL_EFFECTIVE_DATE` на дату выкладки: политика конфиденциальности и cookies
   изменились.
3. Пересобрать образы web и gateway (CSP шлюза).

## Проверка приложения в DebugView

1. Собрать и поставить debug-сборку с ID Firebase:
   `flutter build apk --debug --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://iqro.forum --dart-define-from-file=config/firebase.json`.
2. Включить отладочный режим на телефоне:
   `adb shell setprop debug.firebase.analytics.app forum.iqro.app`
   (выключить: `adb shell setprop debug.firebase.analytics.app .none.`).
3. В приложении нажать «Принять», открыть суру, включить аудио.
4. Firebase → проект «IQRO» → Analytics → DebugView (или GA4 → Администратор → DebugView):
   события появляются через несколько секунд. В обычных отчётах GA4 — через 24–48 часов.
