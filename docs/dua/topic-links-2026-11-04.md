# Ссылки сайта на тематические карточки в приложении

Сделано 4 ноября 2026 года. Найдено при проверке на телефоне: ссылка сайта
`https://iqro.forum/ru/dua/topics/morning` открывалась в приложении как «Это ду’а недоступно».

## Причина

Сайт открывает карточку темы по адресу `/{locale}/dua/topics/{topic}`
(`services/web/app/[locale]/dua/topics/[topic]/page.tsx`). Приложение убирает язык из адреса
(`normalizeLocalizedDuaDeepLink` в `clients/iqro_mobile/lib/app/router.dart`), но маршрута для
тем у него не было: `/dua/topics/morning` совпадал с `/dua/:collection/:sourceNumber` и читался
как ду’а № 0 сборника «topics».

## Как устроено

- Маршрут `/dua/topics/:topic` стоит в `router.dart` перед `/dua/:collection/:sourceNumber`.
- Он открывает тот же экран, что и нажатие на карточку: `DuaScreen(initialTopic: …)`. Тема
  ищется по `id` в `duaTopics` (`dua_topic_catalog.g.dart`, копия
  `services/web/lib/dua-topic-catalog.json`). У «morning» и «evening» лента подставляет вариант
  своего времени (`timeOfDay`), как описано в `morning-evening-readings-2026-11-03.md`.
- Тема из нескольких глав сначала показывает список глав, как и на сайте.
- «Назад» возвращает в каталог ду’а, как после нажатия на карточку.
- Неизвестная тема (например, удалённая из каталога) открывает каталог ду’а без ошибки. Сайт
  на такой адрес отвечает 404.
- Android (`android:pathPrefix="/{locale}/dua/"`) и iOS (`/{locale}/dua/*` в
  `services/web/lib/mobile-association.ts`) уже передавали такие ссылки приложению — менять их не
  понадобилось.

## Остальные адреса ду’а

Проверено тестом `every site Dua address opens its own app route`
(`test/core/deep_link_configuration_test.dart`) для ru, en, ar, tr — разбираются как раньше:

| Сайт | Маршрут приложения |
|---|---|
| `/{locale}/dua` | `/dua` — каталог |
| `/{locale}/dua/{collection}/{number}` | `/dua/:collection/:sourceNumber` — отдельное ду’а |
| `/{locale}/dua/{collection}/categories/{slug}` | `/dua/:collection/categories/:category` — глава |
| `/{locale}/dua/{slug}` | `/dua/:id` — глава по старой ссылке |
| `/{locale}/dua/topics/{topic}` | `/dua/topics/:topic` — тема (новое) |

`/{locale}/dua/favorites` на сайте — избранное; в приложении этот адрес, как и прежде, попадает в
`/dua/:id` и открывает каталог, а не избранное. В эту правку не входит.
