# Pinned Quran.Foundation Mushaf pixel renderer

Этот executable реализует JSON contract backend-команды
`prepare_qf_mushaf_native_pages`. Он предназначен только для release-пакета, в котором уже
есть официально разрешённые fonts, точная page/word geometry, декоративные page backgrounds и
license evidence.

Renderer не скачивает fonts, Quran data или Chromium, не использует сеть и не имеет
system-serif fallback. Если хотя бы один glyph отрисован не из закреплённого custom font,
проверка Chrome DevTools Protocol останавливает страницу до создания WebP.

## Почему assets не находятся в Git

Quran.Foundation Content Sync возвращает metadata, page mapping, слова и line numbers, но не
font/image files и не точную координатную геометрию страницы. Официальные
[Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/) отдельно указывают,
что Content Sync offline-storage exception не распространяется на Mushaf fonts/images.
[Mushaf Fonts and Images](https://api-docs.quran.foundation/legal/mushaf-fonts-and-images/)
называет поставщиками resources `1` и `5` King Fahd Glorious Quran Printing Complex, а для
resource `19` также Dar Al Maarifah, и требует обратиться к поставщику для caching/offline use.

Поэтому репозиторий намеренно не содержит скачанный CDN font и не маскирует отсутствие
координат приблизительной 15-row CSS сеткой. Готовый запрос официального пакета и письменного
разрешения находится в
[`docs/sign-offs/kfgqpc-production-files-request.md`](../../docs/sign-offs/kfgqpc-production-files-request.md).

## Что проверяет executable

- SHA-256 самого `assets.lock.json`, Node.js, Chromium, `cwebp`, evidence, font, geometry и каждого
  page background, а также platform и digest неизменяемого container image;
- точное совпадение QF `source_checksum_sha256` с allowlist release-пакета;
- resources только `1`, `5`, `19`; resource `11` всегда отклоняется;
- `geometry.json` содержит страницы `1..604` без пропусков;
- каждая страница содержит точное множество `(source_id, position_in_page, line_number)` и
  SHA-256 точного QF glyph-текста из синхронизированного snapshot;
- каждый word box находится внутри canonical page без растяжения glyph;
- WOFF2 действительно загружен как custom font, и Chromium не применил fallback ни к одному
  слову;
- browser network полностью заблокирован;
- PNG строится в одном canonical resolution, а варианты кодируются pinned `cwebp` с
  `-lossless -exact -metadata none`;
- процесс запускает Chromium и `cwebp` через argv с `shell=false`.

Пропущенные заголовки сур, басмала, орнаменты и номер страницы должны находиться в официальном
page background. Renderer никогда не реконструирует их обычным Unicode или системным шрифтом.
Для Unicode-font resource `5` используются только неизменённые QF Content Sync word glyphs,
закреплённые `source_checksum_sha256` и индивидуальным `text_sha256`, с оригинальным KFGQPC
font; произвольный Unicode-текст или автоматически построенные подписи контракт не принимает.

## Формат release-пакета

Скопируйте `assets.lock.example.json` в отдельное закрытое evidence/artifact storage. Example
намеренно имеет `decision=pending`, нулевые SHA и не может пройти gate.

Для resource `5` lock содержит один WOFF2 и один geometry manifest. Для page-font resources
`1`/`19` `fonts_manifest` должен иметь объект `fonts` с ключами `1..604`; каждый элемент содержит
относительный `path` и SHA-256 WOFF2. `geometry.json` также обязан иметь `pages 1..604`.

Каждая page geometry содержит:

- pinned PNG/WebP background без Quran word text, но с официальными decorations/headings;
- `words` с `source_id`, `position_in_page`, `line_number`, `text_sha256`;
- целочисленные `x`, `y`, `width`, `height`, `font_size` в canonical pixels;
- `anchor`: `start`, `center` или `end`.

Geometry и backgrounds должны происходить из официального provider package или из письменно
разрешённого неизменяющего преобразования. Ручная аппроксимация не является release source.

## Установка runtime

Установка Node dependencies не скачивает browser:

```bash
cd ops/qf-mushaf-renderer
npm ci --ignore-scripts
npm test
```

Node.js, Chromium и `cwebp` устанавливаются из проверенного immutable container/internal artifact
mirror. Их полные версии и SHA-256 записываются в lock. Нельзя использовать плавающий системный
runtime или Chrome.

```bash
export IQRO_QF_RENDERER_ASSET_LOCK=/opt/iqro/qf-renderer/release/assets.lock.json
export IQRO_QF_RENDERER_ASSET_LOCK_SHA256='<sha256 assets.lock.json>'
export IQRO_QF_RENDERER_CONTAINER_IMAGE_DIGEST='sha256:<digest pinned in assets.lock.json>'
export IQRO_QF_CHROMIUM_EXECUTABLE=/opt/iqro/qf-renderer/runtime/chrome-headless-shell
export IQRO_QF_CWEBP_EXECUTABLE=/opt/iqro/qf-renderer/runtime/cwebp

./bin/qf-mushaf-renderer.mjs --version
```

`--version` проверяет lock и runtime до того, как Django зафиксирует renderer version. Runner
должен быть непривилегированным пользователем в container image, указанном по digest: Chromium
sandbox остаётся включённым, и executable не добавляет `--no-sandbox`.

## Prepare, воспроизводимость и publish

```bash
cd services/backend

uv run python manage.py prepare_qf_mushaf_native_pages \
  --mushaf 5 \
  --render-version kfgqpc-authorized-1.0.0 \
  --renderer ../../ops/qf-mushaf-renderer/bin/qf-mushaf-renderer.mjs \
  --first-page 1 \
  --limit 25 \
  --widths 720,1080,1440
```

Для reproducibility gate одну контрольную страницу нужно отрендерить дважды в чистые output
directories и сравнить SHA-256 каждого WebP. Затем выполняется полный batch, curated visual
review страниц `1`, `2`, `50`, `255`, `604` и только после sign-off:

```bash
uv run python manage.py publish_qf_mushaf_native_pages \
  --mushaf 5 \
  --render-version kfgqpc-authorized-1.0.0
```

Новый QF snapshot меняет source checksum и автоматически закрывает старую публикацию. Для нового
snapshot требуется новый asset lock, geometry audit, render version и sign-off.
