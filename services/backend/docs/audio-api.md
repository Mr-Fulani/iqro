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
В публичный каталог и playback endpoints попадают декламации с полным набором из 114
треков уровня суры. Исключение — записи «только для вкладки Аудио»
(`listening_only`): они видны с любым числом сур и остаются в каталоге после смены
активной версии текста Корана. Пилотные и прерванные импорты остаются доступны
оператору в Django Admin, но не создают дубли чтецов и не дают пользователю выбрать
неработающий каталог `1/114`.

- `GET /api/v1/reciters`
- `GET /api/v1/reciters/{uuid}`
- `GET /api/v1/recitations?reciter_id={uuid}&quran_edition=madani-hafs&style=murattal`
- `GET /api/v1/recitations/{uuid}`
- `GET /api/v1/recitations/{uuid}/tracks?scope=surah`
- `GET /api/v1/recitations/{uuid}/surahs/{surah}`
- `GET /api/v1/recitations/{uuid}/ayahs/{surah}/{ayah}`
- `GET /api/v1/variants/{variant_id}/surahs/{surah}`
- `GET /api/v1/variants/{variant_id}/surahs/{surah}/ayahs/{ayah}`
- `GET /api/v1/quran-foundation/ayah-recitations`
- `GET /api/v1/quran-foundation/ayah-recitations/{source_id}/surahs/{surah}`

## Recitation roles and coverage

`RecitationEdition.id` is the stable identifier of a concrete audio variant. A
`Reciter` is only the person profile; clients must persist and send the variant
ID when selecting playback.

The provider-neutral variant resolver accepts the native UUID directly and uses a
namespaced ID for ayah-by-ayah providers:

```text
<recitation-edition-uuid>
qf-ayah:<environment>:<source_id>:<quran-edition-version-uuid>
```

Both generic variant endpoints return the same typed delivery contract. A surah
track may have one full-file URL plus optional timed ayah ranges; an ayah-by-ayah
variant returns one external URL per ayah with `start_ms` and `end_ms` set to
`null`. Untimed and partial variants remain resolvable for ordinary listening
when a track exists, but the role-aware resolver rejects them for ayah playback
and memorization unless the advertised capability is available.

The recitation catalog is additive and returns role capabilities alongside the
legacy `timings` fields:

```json
{
  "id": "019c...",
  "coverage": {
    "track_count": 114,
    "surah_count": 114,
    "expected_ayahs": 6236,
    "timed_ayahs": 6236,
    "complete": true,
    "timings_complete": true,
    "surah_numbers": [1, 2, "…", 114]
  },
  "timings": {
    "available": true,
    "segment_count": 6236,
    "complete": true
  },
  "capabilities": {
    "listen": true,
    "ayah_playback": true,
    "memorization": true,
    "offline": false
  },
  "teaching_default": false
}
```

`teaching_default` marks the one recitation the Mushaf reader, Memorization and
the salah and tajweed courses play until the user picks a reciter: the admin's
choice in «Аудио → Учебный чтец» (`AudioCatalogSettings`), else the newest
published recitation whose code is `QURAN_TEACHING_RECITATION_CODE` (al-Husary's
muallim recording, `qf-12-muallim-01a15bc65dc9`, by default). It is `true` for at
most one recitation and only while that recitation is published, not
listening-only and has verified timings; when none carries it, clients keep
their own fallback rules. The listening player ignores it. The flag is read with
the catalog, so a change reaches the site within the API's 5-minute cache and
the app within its 12-hour catalog cache.

`listen` describes a streamable surah catalog. `ayah_playback` and
`memorization` require verified timing coverage for every ayah in the active
Quran edition and are always `false` for a `listening_only` recitation, even a
timed one. `coverage.surah_numbers` lists the surahs a recitation holds, so
clients offer only those surahs and skip the gaps of a partial listening
recording; clients treat a missing list as all 114. `offline` reflects the redistribution right and does not imply
that a client has downloaded the package. Older clients may continue using
`timings.available`; new clients must use capabilities and coverage to avoid
offering partial or untimed variants in Mushaf and Memorization.

The Memorization plan endpoint accepts a `recitation_id` only when the variant
is public, streamable, belongs to the same Quran edition as the selected ayahs,
and has verified timing segments for the complete requested range. A source
without timing tags remains valid for ordinary listening but is rejected for a
timed memorization plan.

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

### Портреты и локализованные биографии чтецов

В Django Admin у чтеца используется поле «Загрузить новый портрет». Оператор выбирает
WebP, JPEG или PNG размером до 50 МБ; backend проверяет фактическую сигнатуру файла,
вычисляет SHA-256, создаёт immutable object key и загружает изображение в настроенное
`MEDIA_OBJECT_STORAGE_*` хранилище. Вводить URL или object key вручную не требуется.

Текущий портрет показывается прямо в форме. Служебный адрес файла доступен только для
чтения в свёрнутом разделе. API возвращает готовый `portrait_url`, построенный
от `PUBLIC_AUDIO_BASE_URL`. Замена портрета создаёт новый versioned key и немедленно
отправляет web-событие инвалидации кэша.

Имя и биография поддерживаются отдельно на арабском, английском, русском и турецком.
Клиенты используют английский текст как fallback, если турецкий вариант ещё не заполнен.

Кураторский каталог содержит профили всех 18 подключённых Quran.Foundation записей
(16 уникальных чтецов: варианты `murattal`/`mujawwad`/`muallim` используют один профиль).
Для каждого профиля заполнены четыре локали, ISO-код страны, публичный URL источника и дата
его проверки. Биографии написаны для IQRO как короткие самостоятельные резюме фактов, а не
скопированы из источников. Миграция дополняет существующий каталог, а QF importer применяет
тот же профиль при развёртывании новой базы данных.

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

### Записи только для прослушивания (Django Admin)

Чтец → «Добавить запись для прослушивания» открывает форму с включённым флагом
«Только для вкладки «Аудио»», подставленным чтецом и изданием `madani-hafs`; код и
версия записи заполняются сами. После сохранения черновика блок «Суры» принимает
несколько MP3 сразу: номер суры берётся из начала имени файла, каждый файл уходит
отдельным запросом (до 512 МБ). Сервер сам измеряет длительность и битрейт (ffprobe),
считает SHA-256, загружает файл create-only под неизменяемым ключом
`audio/recitations/<code>/<version>/surah-NNN-<sha>.mp3`, проверяет публичный URL
(`200`, размер, `audio/mpeg`, strong ETag, годовой `immutable`-кэш) и только потом
создаёт трек. Статус «Опубликовано» ставит дату публикации сам; публиковать можно с
одной сурой. Поля источника и прав необязательны и свёрнуты: воспроизведение включено
по умолчанию, скачивание выключено. В опубликованную запись «только для Аудио» можно докладывать новые суры,
уже загруженные не меняются. Такая запись никогда не попадает в Мусхаф и Заучивание.
Офлайн-пакет по-прежнему требует все 114 сур и полный contract report.

Через gateway этот путь принимает тело до 520 МБ без буферизации и ждёт ответа до
10 минут; бэкенд кладёт тело запроса во временный том `backend-uploads`
(`TMPDIR=/var/tmp/iqro-uploads`), а не в 64 МБ `/tmp` в памяти. TLS-proxy перед
gateway должен пропускать такие запросы (Cloudflare proxy на тарифах Free/Pro режет
тело запроса на 100 МБ).

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

Ayah-by-ayah recitations — отдельный официальный каталог: его IDs нельзя передавать в chapter
endpoints. Iqro хранит все 6 236 URL каждого source, сгруппированные в 114 строк по суре, и
возвращает их отдельным API. Полный sync выполняется одной командой:

```bash
python manage.py sync_quran_foundation_ayah_audio --edition madani-hafs
```

Production-проверка синхронизировала 12/12 resources: 1 368 chapter groups и 74 832 ayah audio
URL. Для каждого source проверены первый и последний MP3 через bounded `HEAD` — 24/24 успешно.
Разрешены только HTTPS origins `verses.quran.foundation` и `mirrors.quranicaudio.com`, реально
возвращённые production API. Файлы не проксируются, не копируются и не разрешены для offline.

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
QF_AYAH_AUDIO_SYNC_ENABLED=true
QF_AYAH_AUDIO_EDITION=madani-hafs
QF_AUDIO_REFRESH_DAYS=5
```

Celery Beat ежедневно запускает `audio.sync_quran_foundation`. Свежие каталоги
пропускаются, но успешная проверка каждого опубликованного QF-чтеца выполняется не реже
заданного интервала (допустимо 1–6 дней). Для доступных ресурсов используется официальный
QF Content Sync с сохранённым checkpoint; для chapter-reciter, которому не соответствует
Content Sync resource, выполняется полная сверка 114 сур. При изменении создаётся новая
immutable-версия, а прежняя атомарно переводится в `withdrawn`.

Отдельная задача `audio.sync_quran_foundation_ayah_catalog` раз в семь дней повторно получает
12 полных списков, проверяет точное множество verse keys активной Hafs edition и CDN samples,
а затем атомарно заменяет только изменившиеся source. Некорректный или неполный source сразу
становится недоступен публичному API.

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
