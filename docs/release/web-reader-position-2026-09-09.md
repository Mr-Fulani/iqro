# Позиция чтения, аудио и поворот экрана — 9 сентября 2026

Ветка: `codex/reader-position-audio-rotation`.

Изменения ограничены `services/web`. Выбор аята обновляет суру, аят, джуз, хизб,
руб аль-хизб и готовый фрагмент плеера. Позиция переносится между текстом и Мусхафом,
в том числе без предварительного выделения аята. Ответ загрузки суры больше не
перемещает пользователя в её начало; устаревшие ответы игнорируются.

Плеер готовит выбранный фрагмент до нажатия Play. Для соседних аятов сохраняется
тот же источник; метаданные таймингов кешируются максимум для трёх сур текущего
чтеца, параллельные запросы объединены. При отсутствии таймингов выбранный аят
не подменяется целой сурой. Отменённый или устаревший play promise не показывает
ложную ошибку поверх нового воспроизведения.

Размер листа пересчитывается ResizeObserver по фактической области читалки.
Автоматическое увеличение текста браузером отключено на странице Корана;
пользовательское масштабирование жестом и настройки доступности viewport сохранены.
Состояние плеера и страницы не перемонтируется при повороте.

## Проверки

13 целевых браузерных сценариев прошли: десктопные поля и один запрос таймингов,
переключение видов в обе стороны, два поворота с проверкой размеров листа и шрифта,
первый запуск реального WAV касанием в landscape и повторный запуск после поворота,
отменённый play promise, отсутствие таймингов, мобильный выбор/пауза/настройки,
диапазон/повтор/паузы/таймер, deep link, переходы по разделам и аятам, синхронизация
page deep link, задержанные тайминги и поздние metadata после смены страницы.

Тест реального аудио использует нативные play/pause/load браузера и корректные
ответы HTTP Range; каталог замокан. Профиль Pixel 7 — эмуляция, физического телефона
нет. Локальные TypeScript и ESLint прошли; полные наборы тестов не запускались.
Артефакты: `/private/tmp/iqro-reader-position-tests-{2,3,4,5}`.

Браузерные особенности проверены по [документации Chrome](https://developer.chrome.com/blog/play-request-was-interrupted)
и [описанию text-size-adjust](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-size-adjust).

## Выпуск

Предыдущая версия staging: `8064be5ca96a96579bc8288e12797eccb8181ac2`,
образ `quran-platform-web:staging-8064be5`. Используется существующий web-only compose
путь с сохранением предыдущего образа и исходников. Backend, данные и release tooling
не меняются. Новый дамп для этих изменений не требуется.

Код: `8e791e7`, merge: `2798dc4e58a53cb6df5eae58e1bfb00c7b39efca`.
Локальная production-сборка и CSS integrity прошли (2 чанка, 117821 байт).

```text
archive=/private/tmp/iqro-reader-position-source-2798dc4.tar.gz
SHA256=9b617811a67bb2ffb9be5c20cc9eac5e5cbde8993104577b44ac248bc212fadc
destination=root@162.55.35.8:/opt/quran/releases/web-reader-position-20260909/source-2798dc4.tar.gz
WEB_IMAGE=quran-platform-web:staging-2798dc4
.deployed-commit=2798dc4e58a53cb6df5eae58e1bfb00c7b39efca
```

Архив проверен по SHA256, исходники распакованы, Docker-образ `quran-platform-web:staging-2798dc4` успешно собран и развёрнут на staging (`https://staging.iqro.forum`).
Контейнер `quran-staging-web-1` получил статус `healthy`, `readiness` вернул `status=ok`, HTTP 200 на `/ru/quran`.
Прежний образ `staging-8064be5` и исходники сохранены в `/opt/quran/releases/web-reader-position-20260909/` для отката.

---

## Выпуск 2 — сохранение позиции чтения (987a612)

**Проблема:** При открытии `/quran` читалка всегда сбрасывалась на страницу 1 вместо
возврата к последнему месту чтения.

**Корень причины (3 бага):**
1. `currentPage` инициализировался как `deepLinkPage || 1` — localStorage не читался.
2. `selectedSurah` инициализировался как `deepLinkSurah` (всегда 1 без URL-параметра).
3. `useEffect getAyahs` сбрасывал `currentPage` к `res[0].pages[0]` при первой загрузке издания.
4. Серверный `getReadingPosition` вызывался только в режиме `after-prayer`, а не при обычном чтении.

**Исправление:**
- Новый модуль `services/web/lib/reading-position-storage.ts` — чистые localStorage-хелперы
  с инжектируемым хранилищем для юнит-тестов.
- `page.tsx`: флаг `hasExplicitDeepLink`; `initialLocalPosition` из localStorage при старте;
  немедленная запись позиции в `writeLocalReadingPosition` до debounced API-вызова;
  guard в `getAyahs` при наличии восстановленной позиции; новый `useEffect` для синхронизации
  серверной позиции (применяется только если серверный `last_read_at` новее локального).
- 4 юнит-теста и 3 Playwright E2E-теста добавлены.

**Проверки:** `typecheck` ✅, `lint` ✅ (0 ошибок), `test:public-contracts` ✅ (9 тестов), `build` ✅.

```text
archive=/private/tmp/iqro-reader-position-source-987a612.tar.gz
SHA256=7fea51e837543e854859c1ae07ea6467c6a9bad803ba7c655193558bdf99a358
destination=root@162.55.35.8:/opt/quran/releases/web-reader-position-20260909/source-987a612.tar.gz
WEB_IMAGE=quran-platform-web:staging-987a612
.deployed-commit=987a6120894084f9328ee6919a71a4fdbd13dae7
```

Образ `quran-platform-web:staging-987a612` собран и развёрнут на staging.
Контейнер `quran-staging-web-1` — статус `healthy`, `readiness` → `status=ok`, HTTP 200 на `/ru/quran`.
