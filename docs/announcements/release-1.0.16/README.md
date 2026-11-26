# Объявление о версии IQRO 1.0.16

Материалы для раздела «Объявления» в админке: тексты на четырёх языках и три картинки шагов.
Объявление одно для приложения и сайта. Публикует его владелец.

Выпуск 1.0.16 (17) опубликован в Google Play 26.11.2026 для всех, в «Последняя версия приложения»
владелец поставил 17. Черновик внесён в админку 26.11.2026, три картинки шагов загружены.
Публикует владелец.

Объявлений о версиях 1.0.14 и 1.0.15 на сайте не было (последнее опубликованное — «IQRO 1.0.13:
проверка чтения без интернета», 18.11.2026; черновик 1.0.14 в админку не вносился). Поэтому главное
из этих двух версий коротко названо в блоке «Что ещё изменилось». Строка про курс намаза верна:
версия курса `2026-11-20` опубликована на рабочем сайте 20.11.2026.

## Настройки

| Поле | Значение |
| --- | --- |
| Вид | Новая версия приложения |
| Важность | обычная |
| Где показывать | пузырёк на главной и лента «Что нового» (без окна с шагами и без push) |
| Значок пузырька | искра |
| Пузырёк | раз в день, не больше 5 показов |
| Языки | русский, английский, арабский, турецкий |
| Платформы | Android |

Платформа только Android: проверки чтения вслух на сайте нет, а приложения для iPhone в магазине
пока нет. Рамка названия суры есть и на сайте с телефона, но отдельного объявления для сайта нет.

## Картинки шагов

Загружаются в блоке «Иллюстрации шагов», одна картинка на все языки.

| Шаг | Файл | Что видно |
| --- | --- | --- |
| 1 | `step-1-surah-frame.webp` | чистый арабский текст, название суры «Аль-Бакара» в узорной рамке, басмала и первый аят |
| 2 | `step-2-stop-no-ghunnah.webp` | аят 67:3: «طِبَاقًا» в конце первой строки, «مَّا» в начале второй, золотая плашка дошла до «فُطُورٍ» |
| 3 | `step-3-vowels.webp` | красная плашка на слове в аяте 2:3 — так выглядит остановка на ошибке |

Все три — неподвижные WebP 720×405 (16:9), каждая меньше 512 КБ, без надписей интерфейса. Вырезаны
из снимков экрана `docs/guides/surah-frame-text/src/app-after.jpg`,
`docs/guides/recitation-check/screens/5-mistake.jpg` и снимка проверки PR #326 на Redmi (запись
аль-Хусари, 67:3 с остановкой на «طِبَاقًا»; снимок осветлён: на телефоне был включён приглушённый
экран, поля по бокам добавлены до 16:9).

## Тексты

### Русский

- Заголовок: IQRO 1.0.16: названия сур в рамке, как в Мусхафе
- Кратко: В чистом арабском тексте названия сур стоят в рамке. При чтении вслух остановка на слове не требует гунны, ложных ошибок в огласовках меньше.
- Текст:

  ```
  Что ещё изменилось в последних версиях:
  • Золотая плашка идёт под словом, которое вы читаете, и пишет, в чём ошибка.
  • Ночной Мусхаф: тёмная страница, цвета таджвида сохраняются.
  • Размер арабского текста меняется двумя пальцами.
  • Чтением можно управлять с экрана блокировки.
  • В курсе намаза озвучены все слова намаза, кроме сур.

  Проверка чтения может ошибаться и не заменяет учителя.
  ```

- Шаг 1: Название суры в рамке — Откройте «Коран» → «Текст» и проведите по аяту вправо. В чистом арабском тексте название суры стоит в рамке, как в Мусхафе.
- Шаг 2: Остановка без гунны — Остановились на слове — гунна слияния со следующим словом не нужна. Пример, 67:3: после остановки на «طِبَاقًا» слово «مَّا» читается без гунны.
- Шаг 3: Меньше ложных ошибок — «Другая огласовка» теперь показывается, только когда написанной огласовки не слышно совсем.

### English

- Title: IQRO 1.0.16: surah names in a Mushaf frame
- Summary: In plain Arabic text surah names now stand in a frame. When you read aloud, a stop on a word needs no ghunnah, and false vowel mistakes are fewer.
- Body:

  ```
  What else has changed in recent versions:
  • A golden plate moves under the word you are reading and says what the mistake is.
  • Night Mushaf: a dark page that keeps the tajweed colours.
  • Pinch with two fingers to resize the Arabic text.
  • Control the recitation from the lock screen.
  • In the prayer course, all the words of the prayer except the surahs now have audio.

  The recitation check can be wrong and does not replace a teacher.
  ```

- Step 1: Surah name in a frame — Open Quran → Text and swipe right on an ayah. In plain Arabic text the surah name stands in a frame, as in the Mushaf.
- Step 2: A stop needs no ghunnah — If you stop on a word, the merging ghunnah with the next word is not required. Example, 67:3: after a stop on «طِبَاقًا», «مَّا» is read without ghunnah.
- Step 3: Fewer false mistakes — “Another vowel” is now shown only when the written vowel is not heard at all.

### العربية

- العنوان: IQRO 1.0.16: أسماء السور في إطار كالمصحف
- الملخص: في النص العربي المجرّد صار اسم السورة في إطار. وعند التلاوة بصوت مسموع لا تُطلب الغنّة بعد الوقف على كلمة، وقلّت الأخطاء الوهمية في الحركات.
- النص:

  ```
  ما الذي تغيّر أيضًا في الإصدارات الأخيرة:
  • لوحة ذهبية تسير تحت الكلمة التي تقرؤها وتبيّن نوع الخطأ.
  • المصحف الليلي: صفحة داكنة مع بقاء ألوان التجويد.
  • غيّر حجم النص العربي بإصبعين.
  • تحكّم في التلاوة من شاشة القفل.
  • في دورة الصلاة صار لكل أذكار الصلاة صوت، ما عدا السور.

  التحقق من التلاوة قد يخطئ ولا يغني عن المعلّم.
  ```

- الخطوة 1: اسم السورة في إطار — افتح «القرآن» ← «النص» واسحب الآية إلى اليمين. في النص العربي المجرّد يظهر اسم السورة في إطار كما في المصحف.
- الخطوة 2: الوقف بلا غنّة — إذا وقفت على كلمة فلا تُطلب غنّة الإدغام مع الكلمة التالية. مثال، 67:3: بعد الوقف على «طِبَاقًا» تُقرأ «مَّا» بلا غنّة.
- الخطوة 3: أخطاء وهمية أقل — «حركة أخرى» تظهر الآن فقط إذا لم تُسمع الحركة المكتوبة إطلاقًا.

### Türkçe

- Başlık: IQRO 1.0.16: sure adları Mushaf'taki gibi çerçevede
- Özet: Yalın Arapça metinde sure adları artık çerçevede. Sesli okumada bir kelimede durunca gunne istenmez, harekelerde yanlış uyarılar azaldı.
- Metin:

  ```
  Son sürümlerde başka neler değişti:
  • Okuduğunuz kelimenin altında altın bir şerit ilerler ve hatanın ne olduğunu yazar.
  • Gece Mushafı: koyu sayfa, tecvid renkleri yerinde.
  • Arapça metnin boyutu iki parmakla değişir.
  • Okumayı kilit ekranından yönetin.
  • Namaz kursunda sureler dışındaki bütün namaz sözleri seslendirildi.

  Okuma kontrolü yanılabilir ve bir hocanın yerini tutmaz.
  ```

- Adım 1: Sure adı çerçevede — «Kur'an» → «Metin» bölümünü açın ve ayeti sağa kaydırın. Yalın Arapça metinde sure adı Mushaf'taki gibi çerçevede durur.
- Adım 2: Durunca gunne gerekmez — Bir kelimede durursanız sonraki kelimeyle idgam gunnesi istenmez. Örnek, 67:3: «طِبَاقًا» üzerinde durunca «مَّا» gunnesiz okunur.
- Adım 3: Daha az yanlış uyarı — «Başka hareke» artık yalnızca yazılan hareke hiç duyulmadığında gösterilir.
