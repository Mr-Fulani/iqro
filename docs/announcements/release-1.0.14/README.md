# Объявление о версии IQRO 1.0.14

Материалы для раздела «Объявления» в админке: тексты на четырёх языках и три картинки шагов.
Объявление одно для приложения и сайта. Публикует его владелец.

Выпуск 1.0.14 (15) собран 20.11.2026 для закрытого тестирования Alpha. Это черновик: в админку он
не внесён. Публиковать стоит после того, как Google одобрит выпуск и он станет доступен
тестировщикам, иначе объявление расскажет о том, чего у людей ещё нет.

Строка про курс намаза («озвучены все слова намаза, кроме сур») верна только после того, как
владелец подпишет и опубликует версию курса `2026-11-20`. Если курс ещё не опубликован, эту строку
нужно убрать на всех четырёх языках.

## Настройки

| Поле | Значение |
| --- | --- |
| Вид | Новая версия приложения |
| Важность | обычная |
| Где показывать | пузырёк на главной и лента «Что нового» |
| Значок пузырька | искра |
| Языки | русский, английский, арабский, турецкий |
| Платформы | Android |

Платформа только Android: проверки чтения вслух и ночного Мусхафа на сайте нет, а приложения для
iPhone в магазине пока нет.

## Картинки шагов

Загружаются в блоке «Иллюстрации шагов», одна картинка на все языки.

| Шаг | Файл | Что видно |
| --- | --- | --- |
| 1 | `step-1-stop-on-word.webp` | арабский текст, золотая плашка под словом «гишавах» в аяте 2:7 |
| 2 | `step-2-night-mushaf.webp` | тёмная страница Мусхафа, начало суры «Аль-Бакара», цвета таджвида на месте |
| 3 | `step-3-lock-screen.webp` | карточка плеера в шторке телефона: «Аль-Бакара · 1–5» и кнопки ⏮ ⏸ ⏭ |

Все три — неподвижные WebP 720×405 (16:9), каждая меньше 512 КБ. Вырезаны из снимков экрана
`docs/guides/recitation-check/screens/9-stop.jpg`, `docs/guides/mushaf-night/src/app-night.jpg` и
`docs/images/media-controls-2026-11-19/1-notification-mushaf.jpg`.

Оговорка та же, что у прошлых выпусков: на третьем кадре есть надписи интерфейса (название суры и
имя чтеца). Правило «на картинке шага не должно быть текста» нарушено осознанно: это живой снимок
экрана.

## Тексты

### Русский

- Заголовок: IQRO 1.0.14: чтение вслух стало удобнее
- Кратко: Золотая плашка идёт под словом, которое вы читаете. Остановка на слове — не ошибка. Появился ночной Мусхаф.
- Текст:

  ```
  Что ещё изменилось:
  • Размер арабского текста меняется двумя пальцами, двойное касание возвращает обычный.
  • Телефон можно повернуть набок, на планшете текст стал удобной ширины.
  • В курсе намаза озвучены все слова намаза, кроме сур.
  ```

- Шаг 1: Читайте вслух — Плашка идёт по словам и ничем не закрывает текст. Остановились на слове перевести дыхание — она подождёт.
- Шаг 2: Ночной Мусхаф — Откройте Мусхаф, коснитесь страницы и нажмите луну вверху справа. Цвета таджвида сохраняются.
- Шаг 3: Экран блокировки — Чтением Мусхафа, ду‘а и заучиванием можно управлять, не открывая приложение.

### English

- Title: IQRO 1.0.14: reading aloud made easier
- Summary: A golden plate moves under the word you are reading. Stopping on a word is not a mistake. Night Mushaf is here.
- Body:

  ```
  What else has changed:
  • Pinch with two fingers to resize the Arabic text; double tap brings back the usual size.
  • The phone can be turned sideways; on tablets the text has a comfortable width.
  • In the prayer course, all the words of the prayer except the surahs now have audio.
  ```

- Step 1: Read aloud — The plate follows your words and covers nothing. Stop on a word to take a breath and it will wait.
- Step 2: Night Mushaf — Open the Mushaf, tap the page and press the moon at the top right. The tajweed colours stay.
- Step 3: Lock screen — Control Mushaf recitation, du‘a and memorisation without opening the app.

### العربية

- العنوان: IQRO 1.0.14: التلاوة بصوت مسموع صارت أسهل
- الملخص: لوحة ذهبية تسير تحت الكلمة التي تقرؤها. الوقف على كلمة ليس خطأً. وأضيف المصحف الليلي.
- النص:

  ```
  ما الذي تغيّر أيضًا:
  • غيّر حجم النص العربي بإصبعين، والنقر المزدوج يعيد الحجم المعتاد.
  • يمكن تدوير الهاتف أفقيًا، وعلى الجهاز اللوحي صار عرض النص مريحًا.
  • في دورة الصلاة صار لكل أذكار الصلاة صوت، ما عدا السور.
  ```

- الخطوة 1: اقرأ بصوت مسموع — اللوحة تتبع كلماتك ولا تغطي النص. إذا وقفت على كلمة لتتنفس انتظرتك.
- الخطوة 2: المصحف الليلي — افتح المصحف، المس الصفحة واضغط على القمر أعلى اليمين. ألوان التجويد تبقى.
- الخطوة 3: شاشة القفل — تحكّم في تلاوة المصحف والأدعية والحفظ دون فتح التطبيق.

### Türkçe

- Başlık: IQRO 1.0.14: sesli okuma artık daha kolay
- Özet: Okuduğunuz kelimenin altında altın bir şerit ilerler. Bir kelimede durmak hata değildir. Gece Mushafı eklendi.
- Metin:

  ```
  Başka neler değişti:
  • Arapça metnin boyutu iki parmakla değişir, çift dokunuş normal boyuta döndürür.
  • Telefon yan çevrilebilir; tablette metin rahat bir genişlikte.
  • Namaz kursunda sureler dışındaki bütün namaz sözleri seslendirildi.
  ```

- Adım 1: Sesli okuyun — Şerit kelimelerinizi izler ve metni kapatmaz. Nefes almak için bir kelimede durursanız bekler.
- Adım 2: Gece Mushafı — Mushaf'ı açın, sayfaya dokunun ve sağ üstteki aya basın. Tecvid renkleri kalır.
- Adım 3: Kilit ekranı — Mushaf okumasını, duaları ve ezberi uygulamayı açmadan yönetin.
