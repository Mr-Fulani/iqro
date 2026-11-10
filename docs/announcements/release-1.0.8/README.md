# Объявление о версии IQRO 1.0.8

Материалы для раздела «Объявления» в админке: тексты на четырёх языках и три живые картинки шагов.
Объявление одно для приложения и сайта. Публикует его владелец.

Черновик внесён в админку 10.11.2026 («Показывать с» — 10.11.2026 20:00 UTC), все три анимированные
картинки загрузились без ошибок.

## Настройки

| Поле | Значение |
| --- | --- |
| Вид | Новая версия приложения |
| Важность | обычная |
| Где показывать | пузырёк на главной и лента «Что нового» |
| Значок пузырька | искра |
| Языки | русский, английский, арабский, турецкий |
| Платформы | сайт, Android, iOS |

## Картинки шагов

Загружаются в блоке «Иллюстрации шагов», одна картинка на все языки.

| Шаг | Файл | Что видно |
| --- | --- | --- |
| 1 | `step-1-mushaf-script.webp` | карточки аятов в начертании Мусхафа и линия «Страница 2» между ними |
| 2 | `step-2-hizb-mark.webp` | перелистывание страницы Мусхафа, плашка «Хизб 6» и подсвеченный аят |
| 3 | `step-3-prayer-month.webp` | календарь намаза на месяц: ноябрь прокручивается, затем декабрь |

Картинки — зацикленные анимированные WebP шириной 720 (шаг 2 — 640), формат 16:9, каждая меньше
512 КБ. Сделаны из записей экрана в `docs/guides/hizb-mark/video`,
`docs/guides/prayer-month-calendar/video` и снимка `docs/guides/mushaf-script-in-text/src/app-cards.jpg`.

Две оговорки:

- На кадрах есть русские подписи интерфейса («Страница 2», «Хизб 6», названия намазов). Правило
  «на картинке шага не должно быть текста» здесь нарушено осознанно: это живая запись экрана.
- Сервер не умеет читать размер анимированного WebP и записывает 0×0. Сайт показывает такую
  картинку по ширине окна, приложение — в рамке 16:9, поэтому картинки и сделаны в 16:9.

## Тексты

### Русский

- Заголовок: IQRO 1.0.8: текст как в вашем Мусхафе
- Кратко: Аяты в начертании выбранного Мусхафа, плашка «Джуз» и «Хизб», календарь намаза на месяц без прокрутки вбок.
- Текст:

  ```
  Что ещё изменилось:
  • Мусхаф можно выбрать прямо в меню на странице Мусхафа.
  • Нижние панели в приложении больше не уходят под кнопки навигации телефона.
  • Избранное обновляется сразу, исправлены мелкие недочёты экранов.
  ```

- Шаг 1: Текст в начертании Мусхафа — Аяты в чтении показаны тем же начертанием, что и выбранный Мусхаф. Между аятами видна линия, где заканчивается страница.
- Шаг 2: Плашка «Джуз» и «Хизб» — Когда вы доходите до начала четверти хизба, на пару секунд появляется плашка, а аят подсвечивается.
- Шаг 3: Календарь намаза на месяц — Все времена намаза на месяц помещаются на экране: прокручивать вбок не нужно.

### English

- Title: IQRO 1.0.8: text just like your Mushaf
- Summary: Ayahs in the script of the Mushaf you chose, a "Juz" and "Hizb" mark, and a monthly prayer calendar with no sideways scrolling.
- Body:

  ```
  What else has changed:
  • You can choose the Mushaf right from the menu on the Mushaf page.
  • Bottom sheets in the app no longer slide under the phone's navigation buttons.
  • Favourites refresh at once, and small screen flaws are fixed.
  ```

- Step 1: Text in the Mushaf script — Ayahs in the reader use the same script as the Mushaf you chose. A line between ayahs shows where the page ends.
- Step 2: The "Juz" and "Hizb" mark — When you reach the start of a quarter of a hizb, a mark appears for a couple of seconds and the ayah is tinted.
- Step 3: Monthly prayer calendar — All prayer times for the month fit the screen: no sideways scrolling.

### العربية

- العنوان: IQRO 1.0.8: النص كما في مصحفك
- الملخص: الآيات برسم المصحف الذي اخترته، وإشعار «الجزء» و«الحزب»، وتقويم الصلاة الشهري دون تمرير جانبي.
- النص:

  ```
  ما الذي تغيّر أيضًا:
  • يمكنك اختيار المصحف من القائمة في صفحة المصحف مباشرة.
  • اللوحات السفلية في التطبيق لم تعد تختفي تحت أزرار التنقل في الهاتف.
  • المفضلة تتحدث فورًا، مع إصلاحات صغيرة في الشاشات.
  ```

- الخطوة 1: النص برسم المصحف — تظهر الآيات في القراءة بالرسم نفسه للمصحف الذي اخترته، وبين الآيات خط يبيّن نهاية الصفحة.
- الخطوة 2: إشعار «الجزء» و«الحزب» — عند الوصول إلى بداية ربع الحزب يظهر إشعار لثوانٍ قليلة وتُظلَّل الآية.
- الخطوة 3: تقويم الصلاة الشهري — جميع أوقات الصلاة للشهر تظهر على الشاشة كاملة دون تمرير جانبي.

### Türkçe

- Başlık: IQRO 1.0.8: metin Mushaf'ınızdaki gibi
- Özet: Ayetler seçtiğiniz Mushaf'ın hattıyla, "Cüz" ve "Hizb" bildirimi, yana kaydırmadan aylık namaz takvimi.
- Metin:

  ```
  Başka neler değişti:
  • Mushaf'ı doğrudan Mushaf sayfasındaki menüden seçebilirsiniz.
  • Uygulamadaki alt paneller artık telefonun gezinme düğmelerinin altında kalmıyor.
  • Favoriler anında yenileniyor, küçük ekran kusurları giderildi.
  ```

- Adım 1: Mushaf hattıyla metin — Okuma ekranında ayetler seçtiğiniz Mushaf'ın hattıyla gösterilir. Ayetler arasındaki çizgi sayfanın bittiği yeri gösterir.
- Adım 2: "Cüz" ve "Hizb" bildirimi — Hizbin bir çeyreğinin başına geldiğinizde birkaç saniyeliğine bildirim görünür ve ayet vurgulanır.
- Adım 3: Aylık namaz takvimi — Ayın bütün namaz vakitleri ekrana sığar: yana kaydırmaya gerek yok.
