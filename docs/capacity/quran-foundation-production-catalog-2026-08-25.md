# Quran.Foundation production catalog verification

Дата: 25 августа 2026 года.

Проверка выполнена локальным backend Iqro с production Client Credentials. Credentials,
access token и полные signed/internal URL в evidence не записывались.

## Итог

| Объект | Результат |
|---|---:|
| Chapter-reciter resources в production-каталоге | 21 |
| Полностью проверено и опубликовано | 18 |
| Исключено fail-closed | 3 |
| Surah tracks | 2 052 |
| Ayah timing segments | 112 248 |
| External streaming renditions | 2 052 |
| Локальные MP3/object blobs | 0 |
| Mushaf resources | 4 |
| Mushaf pages | 2 416 |
| Positioned Mushaf words | 334 660 |

Каждый опубликованный чтец имеет ровно 114 surah tracks и 6 236 ayah segments. Аудио не
копировалось на VPS/R2: БД хранит проверенную внешнюю HTTPS-ссылку, фактический
`Content-Length`, метаданные и таймкоды.

## Исключённые upstream resources

| Source | Где | Безопасная причина отказа |
|---:|---|---|
| 161 | сура 13, аят 2 | диапазон `0..35210` повторяет предыдущий аят |
| 168 | сура 33, аят 7 | нулевой диапазон `0..0` после начавшейся записи |
| 173 | сура 1, аят 1 | нулевой диапазон `80..80` |

Ни один из трёх sources не создал частичную публичную recitation. Management command
продолжила остальные позиции, сохранила 18 валидных и завершилась с non-zero status, явно
перечислив `161, 173, 168`.

## Воспроизводимая команда

```bash
python manage.py sync_quran_foundation_audio \
  --all-reciters --all-surahs --confirm-full-catalog --resume \
  --content-version 2026.08.25-production \
  --edition madani-hafs \
  --publish
```

Первый запуск был прерван падением Docker Desktop после заполнения локального диска. После
очистки только build/cache artifacts Docker был перезапущен; PostgreSQL volume сохранил шесть
завершённых recitations. `--resume` пропустил их и закончил весь каталог без дублирования.

## Mushaf Content Sync

Production bootstrap `mushafs:*` вернул IDs `1`, `5`, `11`, `19`, 2 416 страниц и 334 660
positioned-word records. Повторный incremental request с сохранённым checkpoint sequence
`1399` не скачивал snapshots повторно. Официальные font endpoints для IDs `1`, `5`, `19`
ответили `200` с CORS и cache headers. ID `11` сохранён, но рендеринг отключён: snapshot даёт
relative word-image keys без документированного публичного asset base URL.

## Проверки кода

- Ruff check и format: passed.
- strict mypy: 172 source files, no issues.
- pytest: 557 passed, 6 skipped.
- coverage: 84.17% при обязательном пороге 80%.
