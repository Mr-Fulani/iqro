# Quran dataset import contract v1

Импорт всегда создаёт черновую неизменяемую версию. Команда импорта не умеет публиковать или активировать контент.

## Файлы

```text
dataset/
├── manifest.json
├── surahs.json
├── ayahs.jsonl
├── pages.jsonl
└── juz.json
```

`manifest.json` содержит метаданные, ожидаемые количества и SHA-256 остальных файлов:

```json
{
  "schema_version": 1,
  "source_version": "source-release-2026-08",
  "content_sha256": "aggregate-checksum",
  "edition": {
    "code": "madani-hafs",
    "version": "1.0.0",
    "name_ar": "مصحف المدينة",
    "name_en": "Madani Mushaf",
    "name_ru": "Мединский мусхаф",
    "riwayah": "Hafs 'an Asim",
    "source_name": "Approved source",
    "source_url": "https://source.example",
    "license_name": "Distribution license",
    "license_url": "https://source.example/license"
  },
  "counts": {"surahs": 114, "ayahs": 6236, "pages": 604, "juz": 30},
  "files": {
    "surahs.json": "sha256",
    "ayahs.jsonl": "sha256",
    "pages.jsonl": "sha256",
    "juz.json": "sha256"
  }
}
```

Aggregate checksum — SHA-256 строки `filename:file_sha256\n`, сформированной для обязательных файлов в лексикографическом порядке имён.

`surahs.json` — упорядоченный массив:

```json
[{"number": 1, "name_ar": "الفاتحة", "name_en": "Al-Fatihah", "name_ru": "Аль-Фатиха", "revelation_type": "meccan", "ayah_count": 7}]
```

Каждая строка `ayahs.jsonl`:

```json
{"surah": 1, "number": 1, "text_uthmani": "...", "text_search": "...", "juz": 1}
```

Каждая строка `pages.jsonl`:

```json
{
  "number": 1,
  "image_width": 1024,
  "image_height": 1536,
  "checksum_sha256": "sha256",
  "assets": [{"format": "webp", "width": 1024, "height": 1536, "path": "quran/madani-hafs/1.0.0/pages/001.webp", "sha256": "sha256", "bytes": 100000}],
  "regions": [{"surah": 1, "ayah": 1, "reading_order": 1, "polygon": [[0.1, 0.1], [0.9, 0.1], [0.9, 0.2]], "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.1}]
}
```

`juz.json` — упорядоченный массив:

```json
[{"number": 1, "start": {"surah": 1, "ayah": 1}, "end": {"surah": 2, "ayah": 141}}]
```

## Команды

```bash
python manage.py import_quran_dataset /path/to/dataset --validate-only
python manage.py import_quran_dataset /path/to/dataset
```

До импорта проверяются размеры файлов, SHA-256, непрерывность нумерации, количества, ссылки джузов, покрытие каждого аята страницей и безопасность относительных путей assets.
