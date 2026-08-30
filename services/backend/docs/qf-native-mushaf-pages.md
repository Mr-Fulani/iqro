# Нативные страницы мусхафов Quran.Foundation

Этот pipeline готовит точные растровые страницы для iOS/Android вне пользовательского HTTP
request. Web-контракт с официальными WOFF2/COLRv1-шрифтами не меняется. Мобильный клиент видит
`native_rendering.status=ready` только после полной публикации всех страниц и всех заявленных
ширин.

## Гарантии

- поддерживаются синхронизированные Quran.Foundation resources `1`, `5` и `19`;
- resource `11` остаётся fail-closed до появления подтверждённого официального asset base URL;
- renderer получает неизменённые `words`, line positions, verse mapping и официальный font
  contract из локального snapshot; backend не нормализует и не переписывает религиозный текст;
- rendition привязана к точному `source_checksum_sha256`, версии и имени renderer;
- ключи имеют вид
  `quran/quran-foundation/native/{environment}/mushaf-{id}/{source_sha}/{render_version}/page-{NNN}/w{width}-{asset_sha}.webp`;
- объекты загружаются через общий create-only object storage с SHA-256 и immutable cache;
- batch ограничен 100 страницами, повторный запуск пропускает уже полностью подготовленные
  страницы;
- частичная подготовка никогда не отдаёт asset URL публичному API.

Модели `QuranFoundationNativePublication` и `QuranFoundationNativePageAsset` доступны в Django
admin только для чтения. В списке видны статус, покрытие страниц, количество объектов, версии,
контрольная сумма manifest и безопасный код последней ошибки.

## Контракт renderer

Backend содержит строгий adapter `ExternalCommandQuranFoundationRenderer`. Реализация executable
находится в `ops/qf-mushaf-renderer`; Chromium и `cwebp` поставляются отдельно из закреплённого
internal artifact/container image. Renderer проверяет SHA-256 asset lock, runtime, provider
evidence, fonts, exact geometry, backgrounds и QF glyph text перед созданием страницы.

Executable обязан поддерживать:

```text
/opt/iqro/bin/qf-mushaf-renderer --version
/opt/iqro/bin/qf-mushaf-renderer render-page --request REQUEST.json --output OUTPUT_DIR
```

Request schema `1` содержит source ID/checksum, официальный font contract, номер страницы,
`lines_per_page`, `verse_mapping`, неизменённый массив `words`, а также список требуемых ширин.
Renderer должен вернуть lossless WebP и записать `OUTPUT_DIR/manifest.json`:

```json
{
  "schema_version": 1,
  "page_number": 1,
  "source_checksum_sha256": "<64 lowercase hex>",
  "lossless": true,
  "assets": [
    {
      "path": "page-001-w720.webp",
      "width": 720,
      "height": 1104,
      "content_type": "image/webp"
    }
  ]
}
```

Пути обязаны быть относительными и оставаться внутри output directory. Backend повторно сверяет
page/source identity, набор ширин, WebP signature, размеры файла и SHA-256 перед create-only
upload. Stderr renderer не сохраняется в БД и не попадает в публичный API.

Executable и install contract готовы, но production pixel release остаётся fail-closed до
получения письменно разрешённого provider package: fonts, exact word geometry, официальные
decoration/background layers и разрешение на WebP derivatives/CDN/native delivery. Точный blocker
зафиксирован в `docs/sign-offs/qf-native-mushaf-renderer-blocker-2026-08-30.md`. Example asset lock
имеет `decision=pending` и не может пройти проверку. До авторизованного release bundle API
корректно отвечает `not_ready`; наличие pipeline не означает готовность пиксельного рендера.

## Prepare и resume

Сначала должен быть завершён `sync_quran_foundation_mushafs`. Затем страницы готовятся bounded
batch-ами. Пример для resource `5`:

```bash
uv run python manage.py prepare_qf_mushaf_native_pages \
  --mushaf 5 \
  --render-version chromium-1.0.0 \
  --renderer /opt/iqro/bin/qf-mushaf-renderer \
  --first-page 1 \
  --limit 25 \
  --widths 720,1080,1440
```

Следующий batch начинается с `26`. Упавший batch запускается повторно с теми же параметрами:
полные страницы будут пропущены, а незавершённые безопасно дорендерятся. Нельзя повторно
использовать `render-version` с другим source checksum, renderer version или набором ширин.

## Публикация

После покрытия всех страниц:

```bash
uv run python manage.py publish_qf_mushaf_native_pages \
  --mushaf 5 \
  --render-version chromium-1.0.0
```

Команда атомарно проверяет точное множество `(page, width)`, наличие всех синхронизированных
страниц, source checksum и создаёт детерминированный manifest checksum. Только после этого версия
становится активной. Старые объекты и строки публикаций не удаляются.

Публичный каталог добавляет обратносуместимое поле `native_rendering`. Page endpoint добавляет
`native_assets`; при отсутствии полной активной версии это всегда пустой массив. Поля
`rendering`, `words` и официальный web font contract сохраняются без изменений.

## Rollback

Чтобы вернуть ранее опубликованную immutable-версию:

```bash
uv run python manage.py publish_qf_mushaf_native_pages \
  --mushaf 5 \
  --render-version chromium-0.9.0 \
  --activate-existing
```

Команда не копирует и не перезаписывает объекты: она атомарно переключает активную публикацию.
Rollback допускается только если source checksum по-прежнему совпадает. После нового upstream
snapshot старые assets остаются для аудита, но API fail-closed и требует новый render-version.

## Release gate

До публикации каждой версии оператор обязан:

1. проверить renderer version и source checksum;
2. выполнить полный prepare для resources `1`, `5`, `19`;
3. визуально сравнить контрольные страницы `1`, `2`, `50`, `255`, `604` с официальным web render;
4. проверить арабские ligatures, номера аятов, sajdah markers и цвета Tajweed;
5. выполнить media CDN HEAD/Range/CORS/cache contract для выборки всех ширин;
6. только после редакционного sign-off запускать publish.

Resource `11` нельзя включать вручную или собирать URL по догадке.
