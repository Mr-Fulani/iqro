# QF native Mushaf renderer production blocker — 2026-08-30

Решение: **blocked pending provider assets and written rights**.

Это техническая фиксация, не юридическое заключение и не религиозно-редакционный sign-off.

## Проверенные факты

1. Quran.Foundation Content Sync хранит Mushaf metadata, page/verse mapping, positioned words и
   line numbers. Font/image files в snapshot не входят.
2. Публичные KFGQPC resource `5` pages содержат слова только на занятых Quran lines. Например,
   page `1` содержит lines `9..15`, page `2` — `10..15`, а страницы с началом сур имеют пропуски
   для title/basmala. Координат слов, page decoration layers и glyph geometry API не возвращает.
3. Официальный Font Rendering guide документирует CDN WOFF2, но рекомендует загружать их с CDN
   во время отображения и не хранить локально.
4. Quran Foundation Developer Terms прямо говорят, что Content Sync offline-storage exception
   не покрывает Mushaf font files или images; для caching/offline use нужно разрешение указанного
   provider.
5. Mushaf Fonts and Images указывает King Fahd Glorious Quran Printing Complex для resources
   `1`/`5`, King Fahd Complex и Dar Al Maarifah для `19` и отдельно говорит, что таблица не даёт
   дополнительных прав на fonts/images.
6. Уже имеющийся `quran-hafs-mushaf.pdf` и построенные из него WebP не закрывают вопрос: provenance
   audit установил metadata `quran.ws`, отсутствие прямого official artifact/checksum/terms и
   запретил считать `madani-hafs@1.0.2` production release candidate.

Официальные источники:

- <https://api-docs.quran.foundation/legal/developer-terms/>
- <https://api-docs.quran.foundation/legal/mushaf-fonts-and-images/>
- <https://github.com/quran/qf-api-docs/blob/main/docs/tutorials/fonts/font-rendering.md>
- <https://api-docs.quran.foundation/docs/tutorials/fonts/page-layout/>

## Почему нельзя автоматически закрыть blocker

Скачивание `UthmanicHafs1Ver18.woff2` и центрирование слов в 15 CSS rows создаёт технически
правдоподобную, но не проверенно точную страницу. Оно не восстанавливает official coordinates,
surah headings, basmala/decorations и может нарушить provider font/image terms. Такой результат
нельзя рекламировать как KFGQPC page rendition.

Нельзя использовать и существующий Madani scan под именем KFGQPC source `5`: это другой source
artifact с незакрытым provenance, а не рендер конкретного QF layout/font release.

## Что уже готово

`ops/qf-mushaf-renderer` содержит production-shaped executable, который:

- принимает backend JSON contract;
- использует pinned Node.js/Chromium/Playwright/cwebp;
- проверяет platform и digest неизменяемого container runtime;
- блокирует сеть и system-font fallback;
- требует SHA-bound provider-approved font, geometry, decorations и license evidence;
- поддерживает Unicode source `5` и page-font architecture `1`/`19`;
- выдаёт детерминированные lossless WebP и manifest;
- fail-closed для source `11`, неизвестного checksum, неполной geometry и неподтверждённых прав.

Он намеренно не может пройти `--version` с example lock и не выдаёт пиксельную заглушку.

## Единственные внешние входы для снятия blocker

1. Ответ provider на готовый запрос
   [`kfgqpc-production-files-request.md`](kfgqpc-production-files-request.md), подтверждающий
   server-side font use, deterministic WebP derivatives, first-party R2/CDN и native delivery.
2. Официальный versioned font/artwork package для нужного resource.
3. Exact page geometry/word coordinates и decoration/background package либо письменное
   разрешение получить эти coordinates неизменяющим способом из официального page artwork.
4. Provider filenames, versions, sizes и SHA-256; сохранённый terms/manual/evidence.
5. Technical reproducibility, religious/editorial, license/legal и product sign-off для
   конкретного immutable render release.

После получения входов остаётся заполнить asset lock, запустить documented prepare batches,
сравнить golden pages и выполнить publish. Изменений HTTP API или мобильного приложения для
этого больше не требуется.
