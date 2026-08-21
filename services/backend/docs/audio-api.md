# Quran audio API and publication contract

Модуль `audio` хранит каталог чтецов, версии чтения, метаданные файлов и проверенные
таймкоды аятов. Django никогда не проксирует аудиобайты: клиенты получают immutable
CDN URL и читают/скачивают файл напрямую.

Для внешних Quran.Foundation assets API возвращает исходный HTTPS URL напрямую. Такие
треки всегда имеют `offline_download_allowed=false`, `immutable=false`,
`range_supported=false`, а `sha256` и `etag` равны `null`: backend не должен заявлять
гарантии собственного object storage для файла провайдера.

## Публичные endpoints

Все endpoints доступны без авторизации, используют cursor pagination для списков и
возвращают `ETag` вместе с
`Cache-Control: public, max-age=300, stale-while-revalidate=86400`.

- `GET /api/v1/reciters`
- `GET /api/v1/reciters/{uuid}`
- `GET /api/v1/recitations?reciter_id={uuid}&quran_edition=madani-hafs&style=murattal`
- `GET /api/v1/recitations/{uuid}`
- `GET /api/v1/recitations/{uuid}/tracks?scope=surah`
- `GET /api/v1/recitations/{uuid}/surahs/{surah}`
- `GET /api/v1/recitations/{uuid}/ayahs/{surah}/{ayah}`

Ответ трека содержит продолжительность, право офлайн-загрузки и asset contract:

```json
{
  "id": "019c...",
  "recitation_id": "019c...",
  "scope": "surah",
  "surah_number": 1,
  "juz_number": null,
  "duration_ms": 91342,
  "timing_version": {
    "version": "1.0.0",
    "source_name": "verified-source",
    "source_checksum_sha256": "...",
    "verified_at": "2026-08-09T00:00:00Z"
  },
  "asset": {
    "url": "https://cdn.example/audio/reader/v1/001.mp3",
    "content_type": "audio/mpeg",
    "codec": "mp3",
    "bitrate_kbps": 128,
    "bytes": 1462272,
    "sha256": "...",
    "etag": "\"...\"",
    "range_supported": true,
    "immutable": true
  },
  "offline_download_allowed": true
}
```

Endpoint суры возвращает один трек и все его сегменты в порядке воспроизведения. Endpoint
аята возвращает тот же asset и один диапазон `start_ms`/`end_ms`; отдельный файл аята не
создаётся. Отсутствие проверенного тайминга даёт `404`, но не мешает воспроизвести всю суру.

Поля AR/EN/RU возвращаются одновременно. Выбор локали выполняет клиент, поэтому
`Accept-Language` не фрагментирует публичный cache и offline-каталог.

## Публикация

Контент сначала создаётся как `draft`. До перевода в `published` оператор обязан:

1. привязать recitation к конкретной активной опубликованной `QuranEditionVersion`;
2. выбрать стиль (`murattal`, `mujawwad` или `muallim`) и заполнить источник, версию,
   SHA-256, правообладателя, лицензию и публичные URL при их наличии;
3. явно зафиксировать решения по streaming и offline redistribution;
4. создать треки только с безопасными относительными object keys, размером и SHA-256;
   для публикации обязателен как минимум один трек уровня суры;
5. для выделения аятов создать проверенную `AudioTimingVersion` и непересекающиеся сегменты;
6. проверить реальное соответствие аудио каноническому тексту и правам распространения.

После публикации метаданные, timing version, треки и сегменты неизменяемы. Исправление
оформляется новой версией с новым object key. Разрешён только переход
`published → withdrawn`; withdrawn и неразрешённый для streaming контент перестают
выдаваться origin API. Обычный withdrawal учитывает публичный cache и не является
механизмом мгновенного отзыва. Критическая ошибка или юридический takedown требуют
одновременно запретить asset на origin/CDN, выполнить purge каталога и выпустить безопасную
замену. До появления автоматизированного revocation workflow нельзя публиковать лицензию,
которая требует гарантированного мгновенного отзыва уже выданного публичного URL.

Реальные записи нельзя загружать или публиковать без документированного разрешения на
мировой streaming и, отдельно, offline redistribution. Автотесты используют только
синтетические метаданные.

### Quran.Foundation pilot sync

Credentials хранятся только в backend environment: `QF_CLIENT_ID`, `QF_CLIENT_SECRET`,
`QF_ENV=prelive|production`. Команда ниже получает метаданные и проверенные таймкоды,
привязывает их к активной Quran edition и публикует внешние треки только для streaming:

```bash
python manage.py sync_quran_foundation_audio \
  --reciter-id 6 --reciter-id 7 --reciter-id 12 \
  --all-surahs \
  --content-version 2026.08.21-production \
  --publish
```

`--surah` можно повторять; `--all-surahs` импортирует все 114 сур. Если оба параметра
отсутствуют, пилот импортирует только суру 1. Параметры `--surah` и `--all-surahs`
взаимоисключающие.
Каждая повторная синхронизация должна получать новую immutable `--content-version`.
Согласно Developer Terms, сохранённые QF metadata необходимо обновлять не реже одного
раза в семь дней, если не используется отдельное разрешение или Content Sync.

## CDN contract

Значение `PUBLIC_AUDIO_BASE_URL` указывает на origin/CDN. Для production CDN обязан
быть явно задан HTTPS URL и поддерживать:

- `GET`, `HEAD`, `Accept-Ranges: bytes`;
- `206 Content-Range` и `416` для некорректного диапазона;
- strong `ETag`, равный заключённому в кавычки SHA-256 из API, а также `Last-Modified`,
  `Content-Length` и сохранённый в метаданных audio MIME;
- `Cache-Control: public, max-age=31536000, immutable` для versioned assets;
- CORS для web origins и expose headers `Accept-Ranges`, `Content-Length`,
  `Content-Range`, `ETag`, `Last-Modified`;
- `Content-Disposition: inline` и `X-Content-Type-Options: nosniff`.

API-флаги `range_supported` и `immutable` описывают обязательный delivery contract, а не
результат runtime-пробы CDN. Этот contract отдельно проверяется в staging перед публикацией.

## Офлайн-загрузка клиента

Если `offline_download_allowed=true`, клиент:

1. скачивает во временный файл и возобновляет через `Range` + `If-Range`;
2. при смене ETag удаляет несовместимую частичную загрузку;
3. после завершения проверяет `bytes` и SHA-256;
4. атомарно переименовывает файл только после полной проверки;
5. никогда не отмечает повреждённый или усечённый файл как установленный.

Общий каталог `download-packages` с отзывом, зависимостями и пакетами full/juz будет
следующим отдельным модулем. Текущий срез уже позволяет безопасно скачать конкретную суру.

Flutter отвечает за background playback, media notification, lock screen controls,
interruption handling и восстановление очереди. Web использует Media Session API в пределах
возможностей браузера. Telegram Mini App гарантирует только foreground playback, пока жив
WebView; backend не обещает воспроизведение после закрытия Telegram.
