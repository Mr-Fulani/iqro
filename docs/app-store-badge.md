# Значок App Store и баннер Safari на сайте

Когда приложение выйдет в App Store, на сайте появятся:

- **значок Apple «Загрузите в App Store»** — на главной в блоке «Мобильное приложение IQRO», на
  остальных страницах — в подвале. Он стоит первым, перед значком Google Play, и один на странице:
  так просит Apple, поэтому подвал главной ряд значков не повторяет. Ведёт на страницу приложения
  в App Store (открывается в новой вкладке);
- **баннер Safari** (Smart App Banner) — полоска IQRO вверху сайта в Safari на iPhone и iPad с
  кнопкой «Загрузить» или, если приложение уже стоит, «Открыть». Его рисует сам Safari по тегу
  `<meta name="apple-itunes-app" content="app-id=…">` в `<head>` каждой страницы;
- **строка Apple о товарных знаках** внизу подвала: Apple просит её там, где стоит значок.

До выхода ничего этого нет: в подвале остаётся отметка «Скоро для iOS», блок на главной показывает
только Google Play.

## Как включить

В день выхода, без нового кода:

1. Взять ссылку на страницу приложения: App Store Connect → приложение → App Information →
   «View on App Store». Вид — `https://apps.apple.com/app/iqro/id1234567890`. Если в ссылке есть
   код страны (`/us/app/…`) или `?l=…`, убрать их: тогда App Store откроется в стране посетителя.
   Короткая ссылка `apple.co/…` не подойдёт: из ссылки берётся номер приложения (`id…`) для
   баннера Safari.
2. Добавить в `.env.production` на сервере строку `WEB_IOS_APP_STORE_URL=<ссылка>`.
3. Пересобрать и перезапустить сайт (`make production-up`): адрес встраивается в образ web при
   сборке (→ `NEXT_PUBLIC_IOS_APP_STORE_URL`), как ссылка на Google Play.
4. Проверить: значок App Store есть в блоке на главной и внизу других страниц, в коде страницы —
   `apple-itunes-app`; в Safari на iPhone вверху появилась полоска IQRO.
5. Отдельной правкой обновить `services/web/public/llms.txt` ([llms-txt.md](llms-txt.md)): в первой
   строке вместо «website and Android app» — сайт и приложение для Android, iPhone и iPad, в
   разделе «Mobile app» — строка со ссылкой на App Store. Файл статичный, переменная его не меняет.

Чтобы выключить — убрать строку из `.env.production` и пересобрать сайт.

## Значок

Файлы `services/web/public/images/store/app-store-{ru,en,ar,tr}.svg` — официальные чёрные значки
Apple из Apple Marketing Toolbox (`toolbox.marketingtools.apple.com`, раздел Badges), по одному
на язык сайта, без изменений. Надписи: «Загрузите в App Store», «Download on the App Store»,
«تنزيل من App Store», «App Store'dan İndirin».

Правила Apple (developer.apple.com/app-store/marketing/guidelines): только официальный значок,
без перерисовки, перекраски и перевода слов «App Store»; высота на экране не меньше 40 px (у нас
48 px, как у Google Play); свободное поле — четверть высоты значка (CSS-класс `.app-store-badge`);
рядом со значками других магазинов — чёрный вариант и первым в ряду; один значок на странице.

Подпись для экранных читалок — `footer.appStoreBadge`, строка о товарных знаках —
`footer.appleTrademarks` в `services/web/lib/messages/`.

## Тесты

- `services/web/lib/store-badge.test.ts` — без ссылки значка нет; для каждого языка есть файл
  Apple нужного размера без скриптов и подпись; номер приложения берётся из ссылки.
- `services/web/e2e/app-store-badge.spec.ts` — один значок на странице: на главной в блоке, на
  других страницах в подвале; четыре языка, первым в ряду, верный адрес, новая вкладка, строка
  Apple; тег баннера стоит в `<head>` и на страницах, которые собираются по запросу; на телефоне
  оба значка помещаются.

Картинки для постов: [guides/app-store-badge](guides/app-store-badge/README.md).
