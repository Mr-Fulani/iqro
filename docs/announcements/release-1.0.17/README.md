# Объявление о версии IQRO 1.0.17

Материалы для раздела «Объявления» в админке: тексты на четырёх языках, без картинок шагов.
Объявление одно для приложения и сайта. Публикует его владелец.

Выпуск 1.0.17 (18) собирается из `main` с PR #333, #335–#341. На 27.11.2026 в «Последней версии
приложения» стоит 17, то есть в Google Play выпуска ещё нет. Публиковать объявление стоит, когда
1.0.17 появится в Google Play, иначе оно расскажет о том, чего у людей ещё нет.

Черновик внесён в админку 27.11.2026 (статус «Черновик»).

## Что вошло и что сюда не попало

| PR | Что видно человеку | В объявлении |
| --- | --- | --- |
| #333 | Время намаза без интернета, календарь месяца, виджеты и напоминания в поясах-ссылках (Кувейт, Малайзия, Босния, Нидерланды, Скандинавия и т. д., 101 пояс) | шаг 1 |
| #336, #341 | База поясов IANA 2026e в приложении и на сервере: Марокко, Британская Колумбия, Альберта, Манитоба больше не сдвинуты на час | шаг 2 |
| #339 | Подсказка «Напоминания о намазе заканчиваются» за сутки до конца плана | шаг 3 |
| #337 | «Настройки» → «Конфиденциальность» открывает политику; микрофон проверки чтения выключается в фоне | «Что ещё изменилось» |
| #338 | Загрузка, прерванная в фоне, докачивается; оборванную закрытием можно удалить | «Что ещё изменилось» |
| #335, #340, остальное из #337–#339 | Подготовка к iPhone, вход для проверяющего Apple, автопроверки | нет: приложения в App Store ещё нет |

## Настройки

| Поле | Значение |
| --- | --- |
| Вид | Новая версия приложения |
| Важность | обычная |
| Где показывать | пузырёк на главной, карточка и лента «Что нового» (без окна с шагами и без push) |
| Значок пузырька | искра |
| Пузырёк | раз в день, не больше 5 показов |
| Языки | русский, английский, арабский, турецкий |
| Платформы | сайт, Android, iOS |

Текст написан так, чтобы был понятен и на сайте: в конце сказано обновить приложение в Google Play.
Про iPhone не говорится.

## Картинки шагов

Не нужны. Новых экранов нет: это исправления времени намаза. Готовые снимки в `docs/guides/`
(экран намаза, виджет, календарь) показывают Москву и русские подписи, а шаги говорят о Кувейте,
Марокко и Канаде, и картинка одна на все языки — такой снимок только запутает.

## Тексты

### Русский

- Заголовок: IQRO 1.0.17: время намаза в Кувейте, Малайзии, Марокко и Канаде
- Кратко: Время намаза, азан и виджеты теперь верны в странах, где они раньше сбивались. Напоминания о намазе больше не закончатся молча.
- Текст:

  ```
  Что ещё изменилось:
  • «Настройки» → «Конфиденциальность» открывает политику конфиденциальности.
  • Загрузка, прерванная, пока приложение было свёрнуто, продолжится, когда вы вернётесь.
  • Загрузку, оборванную закрытием приложения, можно удалить в «Офлайн-хранилище».
  • Микрофон проверки чтения выключается, когда приложение уходит в фон.

  Обновите IQRO в Google Play.
  ```

- Шаг 1: Время намаза в вашей стране — В Кувейте, Малайзии, Боснии, Нидерландах, Скандинавии и ещё многих странах время намаза теперь считается и без интернета, в календаре на месяц, виджетах и напоминаниях.
- Шаг 2: Новые часы в Марокко и Канаде — Учтены новые правила часов в Марокко, Британской Колумбии, Альберте и Манитобе: время намаза и азан больше не сдвинуты на час.
- Шаг 3: Напоминания не закончатся молча — Напоминания о намазе ставятся на месяц вперёд. Если долго не открывать IQRO, за сутки до конца придёт подсказка: откройте приложение, и напоминания продлятся.

### English

- Title: IQRO 1.0.17: prayer times in Kuwait, Malaysia, Morocco and Canada
- Summary: Prayer times, adhan and widgets are now right in countries where they used to go wrong. Prayer reminders no longer run out silently.
- Body:

  ```
  What else has changed:
  • Settings → Privacy opens the privacy policy.
  • A download interrupted while the app was in the background continues when you come back.
  • A download cut off by closing the app can be deleted in Offline storage.
  • The recitation check microphone turns off when the app goes to the background.

  Update IQRO on Google Play.
  ```

- Step 1: Prayer times in your country — In Kuwait, Malaysia, Bosnia, the Netherlands, Scandinavia and many other countries prayer times now work offline, in the monthly calendar, widgets and reminders.
- Step 2: New clocks in Morocco and Canada — The new clock rules of Morocco, British Columbia, Alberta and Manitoba are in: prayer times and adhan are no longer an hour off.
- Step 3: Reminders won't run out silently — Prayer reminders are set a month ahead. If you don't open IQRO for a long time, a hint comes a day before they end: open the app and the reminders go on.

### العربية

- العنوان: IQRO 1.0.17: مواقيت الصلاة في الكويت وماليزيا والمغرب وكندا
- الملخص: صارت مواقيت الصلاة والأذان والأدوات صحيحة في البلدان التي كانت تختلّ فيها. ولن تنتهي تذكيرات الصلاة دون تنبيه.
- النص:

  ```
  ما الذي تغيّر أيضًا:
  • «الإعدادات» ← «الخصوصية» يفتح سياسة الخصوصية.
  • التنزيل الذي انقطع والتطبيق في الخلفية يُستأنف عند عودتك.
  • التنزيل الذي انقطع بإغلاق التطبيق يمكن حذفه في «التخزين دون إنترنت».
  • ميكروفون التحقق من التلاوة يُطفأ عندما ينتقل التطبيق إلى الخلفية.

  حدّث IQRO من Google Play.
  ```

- الخطوة 1: مواقيت الصلاة في بلدك — في الكويت وماليزيا والبوسنة وهولندا والدول الإسكندنافية وبلدان كثيرة أخرى صارت المواقيت تُحسب دون إنترنت وفي تقويم الشهر والأدوات والتذكيرات.
- الخطوة 2: توقيت جديد في المغرب وكندا — أُخذت قواعد التوقيت الجديدة في المغرب وكولومبيا البريطانية وألبرتا ومانيتوبا: المواقيت والأذان لم تعد متأخرة أو متقدمة بساعة.
- الخطوة 3: التذكيرات لن تنتهي فجأة — تُجدول تذكيرات الصلاة لشهر مقدمًا. إذا لم تفتح IQRO مدة طويلة يصلك تنبيه قبل نهايتها بيوم: افتح التطبيق فتستمر التذكيرات.

### Türkçe

- Başlık: IQRO 1.0.17: Kuveyt, Malezya, Fas ve Kanada'da namaz vakitleri
- Özet: Namaz vakitleri, ezan ve widget'lar daha önce kaydığı ülkelerde artık doğru. Namaz hatırlatmaları artık sessizce bitmiyor.
- Metin:

  ```
  Başka neler değişti:
  • Ayarlar → Gizlilik, gizlilik politikasını açar.
  • Uygulama arka plandayken yarıda kalan indirme, geri döndüğünüzde devam eder.
  • Uygulama kapatılınca yarıda kalan indirme Çevrimdışı depolama'dan silinebilir.
  • Okuma kontrolünün mikrofonu, uygulama arka plana geçince kapanır.

  IQRO'yu Google Play'den güncelleyin.
  ```

- Adım 1: Ülkenizde namaz vakitleri — Kuveyt, Malezya, Bosna, Hollanda, İskandinavya ve daha birçok ülkede vakitler artık internetsiz, aylık takvimde, widget'larda ve hatırlatmalarda hesaplanıyor.
- Adım 2: Fas ve Kanada'da yeni saatler — Fas, Britanya Kolumbiyası, Alberta ve Manitoba'nın yeni saat kuralları eklendi: namaz vakitleri ve ezan artık bir saat kaymıyor.
- Adım 3: Hatırlatmalar sessizce bitmez — Namaz hatırlatmaları bir ay önceden kurulur. IQRO'yu uzun süre açmazsanız bitmeden bir gün önce uyarı gelir: uygulamayı açın, hatırlatmalar devam etsin.
