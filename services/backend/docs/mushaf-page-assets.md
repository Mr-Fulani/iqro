# Конвейер визуальных страниц мусхафа

## Назначение

Команда `prepare_mushaf_pages` подготавливает переносимый, проверяемый набор визуальных
страниц из закреплённого PDF. Она предназначена для операторского этапа до загрузки в
S3/CDN и до редакционной публикации.

Команда не изменяет исходный PDF, не обращается к моделям Django, не импортирует
`QuranEditionVersion` и не публикует контент.

Без `--spec` используется совместимый закреплённый профиль текущего Hafs PDF. Для другого
издания команда получает SHA-256, количество cover/logical страниц, MediaBox логических
страниц, обязательные metadata и edition/riwayah из отдельной JSON asset build-spec. Эти данные
записываются в manifest schema v2 и затем проверяются командой публикации.

## Закреплённый источник

Для текущего источника зафиксированы следующие инварианты:

- файл: `quran-hafs-mushaf.pdf`;
- SHA-256: `76c690a92e0b464377e765f75d76976cc432877d297091a863b424ec782d234a`;
- 605 PDF-страниц;
- PDF-страница 1 - обложка и никогда не рендерится как страница мусхафа;
- PDF-страницы 2-605 соответствуют логическим страницам 1-604;
- MediaBox каждой страницы: `0 0 900 1379.25 pt`;
- поворот каждой страницы: 0 градусов;
- обязательные metadata-поля `Title`, `Author`, `Creator`, `Producer` проверяются;
- зашифрованные PDF и PDF с JavaScript отклоняются.

PDF состоит из векторных outlines и не имеет пригодного текстового слоя. Поэтому этот
конвейер формирует только визуальные assets. Канонический текст, координаты аятов и
семантическая навигация должны поступать из отдельно проверенного набора данных.

## Зависимости

Нужны Python/Django-зависимости backend и системные утилиты:

- `pdfinfo` и `pdftoppm` из Poppler;
- `cwebp` из WebP tools.

Они включены в отдельный слой `asset-tooling` файла `Dockerfile`. Боевой API-образ
`runtime` не содержит тяжёлые утилиты подготовки assets. Локально команда заранее
проверяет наличие утилит и записывает их версии в manifest.

## Режимы запуска

Все примеры выполняются из `services/backend`.

Только проверка источника, без целевого каталога и рендера:

```bash
uv run python manage.py prepare_mushaf_pages \
  ../../quran-hafs-mushaf.pdf \
  --validate-only
```

Проверка источника, внешних утилит и плана, без записи файлов:

```bash
uv run python manage.py prepare_mushaf_pages \
  ../../quran-hafs-mushaf.pdf \
  --output ../../tmp/mushaf-pages-check \
  --first-page 1 \
  --last-page 10 \
  --dry-run
```

Безопасный тестовый рендер небольшого диапазона:

```bash
uv run python manage.py prepare_mushaf_pages \
  ../../quran-hafs-mushaf.pdf \
  --output ../../tmp/mushaf-pages-001-003 \
  --first-page 1 \
  --last-page 3
```

Полный production-набор следует запускать только после проверки тестового диапазона:

```bash
uv run python manage.py prepare_mushaf_pages \
  ../../quran-hafs-mushaf.pdf \
  --output /data/builds/hafs-pages-v1
```

По умолчанию создаются lossless WebP-варианты шириной 480, 900 и 1800 px. Свой набор
задаётся повторяющимся параметром:

```bash
uv run python manage.py prepare_mushaf_pages \
  ../../quran-hafs-mushaf.pdf \
  --output ../../tmp/mushaf-custom \
  --first-page 1 \
  --last-page 3 \
  --variant-width 600 \
  --variant-width 1200
```

Ширина должна находиться в диапазоне 240-4096 px. Для текущего Hafs-профиля логические
страницы задаются в диапазоне 1-604; для другого издания верхнюю границу и число пропускаемых
cover pages определяет его `--spec`.

`--expected-sha256` предназначен только для совместимого Hafs-профиля. Для другого издания
нужно использовать `--spec`; изменение checksum само по себе не отменяет проверки структуры,
metadata, количества страниц и edition identity.

Минимальная asset build-spec для другого издания выглядит так (placeholder необходимо заменить
фактическими проверенными значениями поставщика):

```jsonc
{
  "schema_version": 1,
  "edition": {
    "code": "madani-warsh",
    "name_ar": "مصحف ورش",
    "name_en": "Warsh Mushaf",
    "name_ru": "Мусхаф Варш",
    "riwayah": "Warsh 'an Nafi",
    "source_name": "Pinned official package",
    "source_url": "https://provider.example/package",
    "license_name": "Reviewed provider terms",
    "license_url": "https://provider.example/terms",
    "surah_count": 114,
    "juz_count": 30
  },
  "pdf_source": {
    "expected_sha256": "<64 lowercase hex characters>",
    "expected_pdf_page_count": "<verified positive integer>",
    "cover_pdf_page_count": "<verified non-negative integer>",
    "logical_page_count": "<verified positive integer>",
    "expected_media_box": [0, 0, "<verified width>", "<verified height>"],
    "required_metadata": {
      "Title": "<verified exact title>"
    }
  }
}
```

Локальный запуск для этой спецификации:

```bash
uv run python manage.py prepare_mushaf_pages \
  /path/to/warsh-mushaf.pdf \
  --spec /path/to/warsh-mushaf-asset-spec.json \
  --output ../../tmp/warsh-pages
```

## Docker

Сначала собирается отдельный операторский образ, не используемый для API:

```bash
docker build --target asset-tooling --tag quran-mushaf-assets .
```

Затем репозиторий и каталог вывода монтируются с подходящими правами. Например, из
`services/backend`:

```bash
docker run --rm \
  -e DJANGO_SETTINGS_MODULE=quran_backend.settings.local \
  -v "$(cd ../.. && pwd):/workspace" \
  quran-mushaf-assets python manage.py prepare_mushaf_pages \
  /workspace/quran-hafs-mushaf.pdf \
  --output /workspace/tmp/mushaf-pages-001-003 \
  --first-page 1 \
  --last-page 3
```

## Структура результата

Целевой каталог создаётся только после завершения и повторной проверки всего диапазона:

```text
hafs-pages-v1/
  manifest.json
  manifest.sha256
  pages/
    001/
      page-001-w0480.webp
      page-001-w0900.webp
      page-001-w1800.webp
```

Каждая запись `assets[]` в `manifest.json` содержит:

- `logical_page` — номер страницы конкретного издания;
- `pdf_page` — исходная PDF-страница с учётом числа закреплённых cover pages;
- `variant` и `format`;
- `dimensions.width` и `dimensions.height`;
- SHA-256, размер в байтах и относительный POSIX-путь;
- параметры диапазона, исходника и версии инструментов на уровне manifest.

`manifest.sha256` проверяется из каталога результата:

```bash
shasum -a 256 -c manifest.sha256
```

Перед загрузкой в объектное хранилище следует дополнительно сверить SHA-256 каждого
asset с `manifest.json`.

## Атомарность и восстановление после ошибки

Рендер выполняется последовательно в случайном staging-каталоге рядом с целевым. Это
гарантирует одну файловую систему для финального атомарного `rename`.

- существующий output никогда не перезаписывается;
- shell не используется, пути передаются внешним процессам отдельными аргументами;
- относительные asset-пути не могут выйти за пределы staging;
- при ошибке, сигнале или неверном asset staging удаляется;
- исходник проверяется по stat fingerprint и SHA-256 до и после рендера;
- manifest записывается только после готовности всех WebP;
- перед promotion повторно проверяются размеры, bytes и SHA-256 всех assets;
- завершённый output появляется целиком либо не появляется вообще.

Для новой попытки используйте новый versioned output либо после ручной проверки удалите
неактуальный каталог. Команда намеренно не имеет флага `--force`.

## Контроль качества и публикация

До полного рендера необходимо визуально проверить минимум первую, типовую среднюю и
последнюю страницу во всех целевых размерах. После полного рендера рекомендуется
выборочная визуальная проверка и автоматическая сверка manifest.

Полученный каталог ещё не является опубликованным контентом. Для новой полной версии уже
работающего интерактивного Мусхафа сначала выполняется только provider-neutral create-only
загрузка объектов:

```bash
python manage.py publish_mushaf_pages \
  /data/builds/hafs-pages-v1/manifest.json \
  --upload --upload-only
```

Затем из последнего проверенного полного dataset и нового manifest создаётся новая полная версия:

```bash
python manage.py upgrade_quran_dataset_assets \
  /data/quran/datasets/madani-hafs-1.0.2 \
  /data/builds/hafs-pages-v1/manifest.json \
  /data/quran/datasets/madani-hafs-1.0.3 \
  --content-version 1.0.3

python manage.py import_quran_dataset /data/quran/datasets/madani-hafs-1.0.3
python manage.py publish_quran_version \
  --edition madani-hafs \
  --content-version 1.0.3 \
  --activate
```

Upgrade-команда сохраняет байт-в-байт корпус, аяты, juz/hizb/rub, hit map и порядок чтения,
заменяя только проверенные page assets и пересчитывая immutable checksums. Она требует наличие
канонического разрешения, относительно которого зарегистрированы координаты, одинаковый набор
ширин на всех страницах и совместимое соотношение сторон. В production активация страницы без
предварительного `--upload` запрещена. Обычный режим `publish_mushaf_pages --activate` создаёт
page-only версию и не должен применяться для обновления уже интерактивного издания.

### Зависимый аудиокаталог при смене версии корпуса

Публичное аудио и его таймкоды привязаны к конкретной активной `QuranEditionVersion`.
Активация новой версии сама по себе **не переносит аудио**. 5 сентября 2026 переход
`1.0.2 → 1.0.3` скрыл 18 релизов/2052 трека, хотя чтецы, портреты и аудиофайлы сохранились.
Для обновления только разрешения изображений предпочтителен режим обновления assets
существующей версии. Если новая полная версия действительно необходима, включайте
зависимые каталоги в план публикации и проверяйте `/reciters` и `/recitations` до/после.

Для уже опубликованного внешнего аудио добавлена безопасная операция:

```bash
python manage.py republish_audio_catalog \
  --edition madani-hafs --source-version 1.0.2 --target-version 1.0.3 \
  --source-release 2026.08.25-production --release-version 2026.09.06-quran-1.0.3
```

По умолчанию это проверка без записи. После проверенного local/offsite backup повторите
с `--apply`. Команда требует совпадения всех аятов по тексту, номеру суры/аята и делениям,
переносит таймкоды на новые UUID аятов, использует прежние Reciter/портреты и URL файлов.
Существующие опубликованные строки не изменяются: создаётся новый аудиорелиз с прежними
правами и provenance. Все релизы одной операции публикуются атомарно; при ошибке новые
записи откатываются. Повторный запуск с теми же параметрами не создаёт дубли.
Managed-object renditions намеренно отклоняются: их уникальные ключи нельзя копировать
или переименовывать этой операцией. Команда не скачивает аудио и не меняет права доступа.

Откат приложения не требует отката этих записей — схема БД не меняется. Если потребуется
снять публикацию нового аудиорелиза, согласуйте отдельно перевод **только** указанного
`release-version` в withdrawn; не удаляйте старые релизы, объекты media или данные
пользователей. Автоматически переключать активную версию Корана обратно нельзя.

### Результат восстановления staging, 2026-09-06

Операция из коммита `09fe96f8136e10a8527e680825e90b8576fc96f1` применена после
проверки PostgreSQL-архива `quran_staging_20260906T012729Z.dump` и полного скачивания
его offsite-копии. Dry-run подтвердил совпадение всех 6236 аятов. Созданы 18 релизов
`2026.09.06-quran-1.0.3`, 2052 трека и 112248 сегментов; прежние релизы и media сохранены.
Повторный dry-run обнаружил ровно 18 существующих релизов, без новых записей.

Публичные `/reciters` и `/recitations` вернули по 18 записей; все релизы имеют
114 сур и 6236 таймкодов. Сохранены шесть ранее загруженных portrait URL; остальные
портреты приложение разрешает через объединённый профиль и существующие assets.
Проверены playback endpoint для аята 2:7, HTTP 206 внешнего аудио, HTTP 200 портрета,
readiness и оба staging-таймера. 129 backend-тестов каталога/API/models/admin прошли.

Это точечная операция с данными, не полный деплой backend: два файла операции
доставлены через `git archive` конкретного коммита и выполнены в существующем контейнере.
Работающий образ и `.deployed-commit` остаются на
`b637fa350d83c49985c55061cf3f6345dd9f467f`; staging.env и схема БД не менялись.
Если клиент уже закэшировал пустой каталог, используйте штатное обновление во вкладке
«Аудио», без очистки данных приложения.
