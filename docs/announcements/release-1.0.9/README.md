# Объявление о версии IQRO 1.0.9

Материалы для раздела «Объявления» в админке: тексты на четырёх языках и три картинки шагов.
Объявление одно для приложения и сайта. Публикует его владелец.

Выпуск 1.0.9 (10) опубликован в закрытом тестировании Alpha 11.11.2026. Черновик внесён в
админку 11.11.2026 («Показывать с» — 11.11.2026 21:00 UTC), три картинки шагов загружены без
ошибок. Публикует владелец.

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
| 1 | `step-1-course-progress.webp` | карточка курса: «2 из 35 уроков», полоса прогресса и кнопка «Продолжить» |
| 2 | `step-2-swipe-hint.webp` | подсказка о свайпе в чтении Корана: рука, боковые панели «Арабский текст» и «Мусхаф» |
| 3 | `step-3-salah-3d-rotate.webp` | 3D-фигура намаза поворачивается, под ней кнопка сброса ракурса |

Все три — WebP 720×405 (16:9), каждая меньше 512 КБ; шаг 1 — неподвижная, шаги 2 и 3 — зацикленные
анимации. Сделаны из записей экрана `docs/guides/courses/video/1-courses-flow.mp4`,
`docs/guides/swipe-hint/video/1-app-hint.mp4` и `docs/guides/salah-3d/video/1-rotate.mp4`.

Те же две оговорки, что и у 1.0.8:

- На кадрах есть русские подписи интерфейса. Правило «на картинке шага не должно быть текста»
  нарушено осознанно: это живая запись экрана.
- Сервер не умеет читать размер анимированного WebP и записывает 0×0, поэтому картинки сделаны
  в 16:9.

## Тексты

### Русский

- Заголовок: IQRO 1.0.9: курсы помнят, где вы остановились
- Кратко: Прогресс курсов сохраняется в аккаунте, приложение открывается быстрее, в Коране появилась подсказка о свайпах.
- Текст:

  ```
  Что ещё изменилось:
  • Приложение открывается быстрее.
  • Ссылки на курсы с сайта открываются сразу в приложении.
  • Мелкие исправления в поиске ду‘а.
  ```

- Шаг 1: Прогресс курсов в аккаунте — Войдите в аккаунт: начните урок на телефоне и продолжите на сайте с того же места.
- Шаг 2: Подсказка о свайпах в Коране — Свайп вправо открывает арабский текст, влево — Мусхаф. Подсказка покажет это при чтении.
- Шаг 3: 3D-намаз: поворот фигуры — Поворачивайте фигуру кнопками и возвращайте исходный ракурс одним нажатием.

### English

- Title: IQRO 1.0.9: courses remember where you stopped
- Summary: Course progress is saved to your account, the app opens faster, and the Quran reader now shows a swipe hint.
- Body:

  ```
  What else has changed:
  • The app opens faster.
  • Course links from the website open straight in the app.
  • Small fixes in dua search.
  ```

- Step 1: Course progress in your account — Sign in: start a lesson on your phone and continue on the website from the same place.
- Step 2: Swipe hint in the Quran — Swipe right for the Arabic text, left for the Mushaf. A hint shows this while you read.
- Step 3: 3D salah: turn the figure — Turn the figure with the buttons and return to the starting view with one tap.

### العربية

- العنوان: IQRO 1.0.9: الدورات تتذكر أين توقفت
- الملخص: تقدّمك في الدورات يُحفظ في حسابك، والتطبيق يفتح أسرع، وفي القرآن تلميح عن السحب.
- النص:

  ```
  ما الذي تغيّر أيضًا:
  • التطبيق يفتح أسرع.
  • روابط الدورات من الموقع تفتح مباشرة في التطبيق.
  • إصلاحات صغيرة في البحث عن الأدعية.
  ```

- الخطوة 1: تقدّم الدورات في حسابك — سجّل الدخول: ابدأ الدرس على الهاتف وأكمله على الموقع من الموضع نفسه.
- الخطوة 2: تلميح السحب في القرآن — اسحب يمينًا للنص العربي ويسارًا للمصحف. يظهر التلميح أثناء القراءة.
- الخطوة 3: الصلاة ثلاثية الأبعاد: تدوير المجسّم — دوّر المجسّم بالأزرار وارجع إلى الزاوية الأولى بضغطة واحدة.

### Türkçe

- Başlık: IQRO 1.0.9: kurslar kaldığınız yeri hatırlıyor
- Özet: Kurs ilerlemesi hesabınıza kaydediliyor, uygulama daha hızlı açılıyor, Kur'an'da kaydırma ipucu var.
- Metin:

  ```
  Başka neler değişti:
  • Uygulama daha hızlı açılıyor.
  • Sitedeki kurs bağlantıları doğrudan uygulamada açılıyor.
  • Dua aramasında küçük düzeltmeler.
  ```

- Adım 1: Kurs ilerlemesi hesabınızda — Giriş yapın: derse telefonda başlayın, sitede kaldığınız yerden devam edin.
- Adım 2: Kur'an'da kaydırma ipucu — Sağa kaydırınca Arapça metin, sola kaydırınca Mushaf açılır. İpucu okurken gösterilir.
- Adım 3: 3D namaz: figürü döndürme — Figürü düğmelerle döndürün, tek dokunuşla ilk görünüme dönün.
