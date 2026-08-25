# Quran audio API and publication contract

Модуль `audio` хранит каталог чтецов, версии чтения, логические `AudioTrack` с проверенными
таймкодами аятов и физические `AudioRendition` economy/standard/high. Django никогда не
проксирует аудиобайты: клиенты получают CDN URL и читают/скачивают файл напрямую.

Для внешних Quran.Foundation assets API возвращает исходный HTTPS URL напрямую. Такие
renditions всегда имеют `offline_download_allowed=false`, `immutable=false`,
`range_supported=false`, а `sha256` и `etag` равны `null`: backend не должен заявлять
гарантии собственного object storage для файла провайдера.

## Публичные endpoints

Все endpoints доступны без авторизации, используют cursor pagination для списков и
возвращают `ETag` вместе с
`Cache-Control: public, max-age=300, stale-while-revalidate=86400`.
В публичный каталог и playback endpoints попадают только декламации с полным набором
из 114 треков уровня суры. Пилотные и прерванные импорты остаются доступны оператору в
Django Admin, но не создают дубли чтецов и не дают пользователю выбрать неработающий
каталог `1/114`.

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
    "url": "https://cdn.example/audio/reader/v1/001-standard.mp3",
    "content_type": "audio/mpeg",
    "codec": "mp3",
    "bitrate_kbps": 128,
    "bytes": 1462272,
    "sha256": "...",
    "etag": "\"edge-observed-value\"",
    "range_supported": true,
    "immutable": true
  },
  "renditions": [
    {
      "id": "019c...",
      "quality": "standard",
      "is_default": true,
      "asset": {
        "url": "https://cdn.example/audio/reader/v1/001-standard.mp3",
        "content_type": "audio/mpeg",
        "codec": "mp3",
        "bitrate_kbps": 128,
        "bytes": 1462272,
        "sha256": "...",
        "etag": "\"edge-observed-value\"",
        "range_supported": true,
        "immutable": true
      }
    }
  ],
  "offline_download_allowed": true
}
```

`asset` всегда повторяет rendition с `is_default=true` и сохраняет совместимость старых
клиентов. Новые Flutter/web/Telegram Mini App клиенты выбирают элемент `renditions` по quality,
сети и настройке пользователя; таймлайн и segment IDs при этом не дублируются.

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
4. создать логические треки и для каждого хотя бы одну rendition с безопасным относительным
   object key либо внешним URL, размером, codec/bitrate и SHA-256 для managed asset; ровно одна
   rendition должна быть default; модель разрешает операторский пилот от одной суры, но
   публичная выдача требует все 114 уникальных треков уровня суры;
5. managed rendition загрузить create-only командой `upload_audio_rendition`, затем прогнать
   public CDN contract для всех `MEDIA_CDN_REQUIRED_ORIGINS` и импортировать report командой
   `record_audio_media_contract`; origin ETag и public edge ETag сохраняются раздельно;
6. для выделения аятов создать проверенную `AudioTimingVersion` и непересекающиеся сегменты;
7. проверить реальное соответствие аудио каноническому тексту и правам распространения.

Пример операторского flow для уже созданной draft rendition:

```bash
python manage.py upload_audio_rendition <rendition-uuid> /data/audio/surah-001-standard.mp3
python3 ../../ops/media/contract.py \
  --manifest /data/reports/audio-release-manifest.json \
  --json-report /data/reports/audio-release-contract.json
python manage.py record_audio_media_contract /data/reports/audio-release-contract.json
```

В contract manifest поле `name` имеет формат `audio-rendition:<rendition-uuid>`, а URL должен
совпадать с `PUBLIC_AUDIO_BASE_URL` и object key. Managed публикация без обоих этапов блокируется.

После публикации метаданные, timing version, треки, renditions и сегменты неизменяемы. Исправление
оформляется новой версией с новым object key. Разрешён только переход
`published → withdrawn`; withdrawn и неразрешённый для streaming контент перестают
выдаваться origin API. Обычный withdrawal учитывает публичный cache и не является
механизмом мгновенного отзыва. Критическая ошибка или юридический takedown требуют
одновременно запретить asset на origin/CDN, выполнить purge каталога и выпустить безопасную
замену. До появления автоматизированного revocation workflow нельзя публиковать лицензию,
которая требует гарантированного мгновенного отзыва уже выданного публичного URL.

Реальные записи нельзя загружать или публиковать без документированного права на выбранный
режим. Для стандартного first-party streaming Quran.Foundation таким документом являются их
актуальные Developer Terms; отдельное письмо не требуется. Эти Terms не разрешают нашему
импортёру rehosting или offline redistribution, поэтому QF rendition всегда сохраняется как
внешний streaming URL с `offline_download_allowed=false`. Автотесты используют только
синтетические метаданные.

### Quran.Foundation import and refresh

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

Полный каталог совместимых chapter-reciter выбирается автоматически. Команда выполняется
последовательно, проверяет каждую суру и внешний `Content-Length`, не скачивает MP3 и может
безопасно продолжиться после прерывания:

```bash
python manage.py sync_quran_foundation_audio \
  --all-reciters --all-surahs --confirm-full-catalog --resume \
  --edition madani-hafs \
  --content-version 2026.08.25-production \
  --publish
```

На полной production-проверке 25 августа 2026 года опубликованы 18 из 21 chapter-reciter:
2 052 surah tracks и 112 248 ayah segments. Provider resources `161`, `168` и `173` исключены
из-за некорректных диапазонов времени. Команда намеренно завершает такой проход с ненулевым
кодом, но сохраняет все полностью проверенные recitations; повторный запуск с `--resume`
пропускает их. Валидатор не ослабляется из-за upstream-ошибки.

`--surah` можно повторять; `--all-surahs` импортирует все 114 сур. Если оба параметра
отсутствуют, пилот импортирует только суру 1 и не показывается публичным клиентам.
Параметры `--surah` и `--all-surahs` взаимоисключающие.
Каждая повторная ручная публикация должна получать новую immutable `--content-version`.
Перед сохранением внешнего track importer всегда сверяет `Content-Length` обычным bounded
`HEAD` на allowlisted Quran.Foundation audio host. Наблюдаемый размер имеет приоритет над
`file_size` metadata: реальный staging probe обнаружил такое расхождение для source reciter `7`.

После полного импорта включите автоматическую проверку в backend environment:

```dotenv
QF_AUDIO_SYNC_ENABLED=true
QF_AUDIO_REFRESH_DAYS=5
```

Celery Beat ежедневно запускает `audio.sync_quran_foundation`. Свежие каталоги
пропускаются, но успешная проверка каждого опубликованного QF-чтеца выполняется не реже
заданного интервала (допустимо 1–6 дней). Для доступных ресурсов используется официальный
QF Content Sync с сохранённым checkpoint; для chapter-reciter, которому не соответствует
Content Sync resource, выполняется полная сверка 114 сур. При изменении создаётся новая
immutable-версия, а прежняя атомарно переводится в `withdrawn`.

Ручная проверка тем же механизмом:

```bash
python manage.py refresh_quran_foundation_audio --force
```

Согласно Developer Terms, сохранённые QF metadata необходимо обновлять не реже одного
раза в семь дней, если не используется отдельное разрешение или Content Sync. Ошибка
обновления не публикует частичный каталог: задача повторяется с exponential backoff, а
счётчик и безопасный код последней ошибки доступны в Django Admin.

## CDN contract

Значение `PUBLIC_AUDIO_BASE_URL` указывает на origin/CDN. Для production CDN обязан
быть явно задан HTTPS URL и поддерживать:

- `GET`, `HEAD`, `Accept-Ranges: bytes`;
- `206 Content-Range` и `416` для некорректного диапазона;
- фактически наблюдаемый strong `ETag`, сохранённый отдельно от SHA-256, а также
  `Last-Modified`, `Content-Length` и сохранённый в rendition audio MIME;
- `Cache-Control: public, max-age=31536000, immutable` для versioned assets;
- CORS для web origins и expose headers `Accept-Ranges`, `Content-Length`,
  `Content-Range`, `ETag`, `Last-Modified`;
- `Content-Disposition: inline` и `X-Content-Type-Options: nosniff`.

API-флаги `range_supported` и `immutable` описывают обязательный delivery contract, а не
результат runtime-пробы CDN. `ops/media/contract.py` отдельно проверяет этот contract в staging
перед публикацией и фиксирует наблюдаемый ETag в JSON evidence.

## Офлайн-загрузка клиента

Если `offline_download_allowed=true`, клиент:

1. скачивает во временный файл и возобновляет через `Range` + `If-Range`;
2. при смене ETag удаляет несовместимую частичную загрузку;
3. после завершения проверяет `bytes` и SHA-256;
4. атомарно переименовывает файл только после полной проверки;
5. никогда не отмечает повреждённый или усечённый файл как установленный.

Общий каталог `download-packages` с отзывом, зависимостями и пакетами full/juz будет
следующим отдельным модулем. Текущий срез уже позволяет безопасно скачать конкретную суру.

Web-клиент строит repeat/range queue по проверенным сегментам, поддерживает учебные паузы,
скорость, sleep timer, сохраняет текущий курсор при browser pause/waiting и использует Media
Session API в пределах возможностей браузера. Это не является гарантией OS background
playback: после закрытия вкладки или приложения воспроизведение может остановиться.

Flutter отдельно отвечает за background playback, media notification, lock screen controls,
native audio focus/interruption handling и восстановление очереди. Telegram Mini App
гарантирует только foreground playback, пока жив WebView; backend не обещает воспроизведение
после закрытия Telegram.
