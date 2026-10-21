# Quran.Foundation production content sync

Для компьютера нового разработчика используйте [локальный запуск](../../../docs/local-development.md):
`make dev-up` и `make dev-data`. Общего тестового API для разработки нет.
Ниже описан операторский импорт; исторические количества относятся к указанным датам.

Iqro использует один confidential backend client. Web, mobile и Telegram Mini App не получают
`QF_CLIENT_SECRET` и не обращаются к Quran.Foundation напрямую.

## Что хранится локально

Mushaf Content Sync разрешён самим Quran.Foundation для локальной копии публичного контента.
Bootstrap `mushafs:*` сохраняет:

- metadata Мусхафа и риваят;
- page/verse mapping;
- слова с page, line и reading positions;
- glyph text и Tajweed CSS metadata, если они присутствуют в source snapshot;
- opaque checkpoint для следующих incremental sync.

На production API 25 августа 2026 года доступны четыре Hafs-layout:

| ID | Название | Font mode | Рендеринг |
|---:|---|---|---|
| 1 | QCF V2 | `v2` | официальный page font, проверен |
| 5 | KFGQPC HAFS | `qpc-hafs` | официальный Unicode font, проверен |
| 11 | Uthmani Recite Quran tajweed images | `img` | данные сохранены, показ отключён |
| 19 | QCF V4 Tajweed | `v4-tajweed` | официальный COLRv1 page font, проверен |

Первый bootstrap сохранил 2 416 страниц и 334 660 positioned-word records. В PostgreSQL слова
группируются по странице, поэтому публичный запрос читает одну строку страницы, а не сотни
отдельных строк. MP3 и Mushaf image blobs этот sync не копирует.

Для ID 11 snapshot содержит относительные image keys вида `w/rq-color/...`, но официальный
публичный base URL не документирован, а проверенный CDN font endpoint для такого пути отвечает
404. Поэтому API возвращает `rendering.available=false`: каталог и разметка сохранены, но клиент
не должен собирать URL самостоятельно. Это снимается после появления подтверждённого origin от
Quran.Foundation. Для ID 1, 5 и 19 API возвращает только проверенные официальные font URL.

Нативные iOS/Android клиенты не должны самостоятельно собирать страницы из WOFF2/COLRv1.
Отдельный versioned pipeline заранее создаёт lossless WebP в managed object storage и включает
`native_rendering` только после полной атомарной публикации. Операторский контракт, prepare,
resume, publish и rollback описаны в
[`docs/qf-native-mushaf-pages.md`](qf-native-mushaf-pages.md).

## Команды

```bash
python manage.py migrate --noinput
python manage.py sync_quran_foundation_mushafs --force
python manage.py sync_quran_foundation_mushafs
```

Без checkpoint первый bootstrap выполняется автоматически. `--force` нужен для явного восстановления. Обычная команда
использует сохранённый token и получает только изменения. `RESOURCE_DELETE` удаляет локальную
копию; create/invalidate/row mutation заменяют только затронутый snapshot.

`--source-id 5` ограничивает синхронизацию основным KFGQPC. Параметр можно повторять;
каждый набор выбранных IDs хранит независимый checkpoint. Этот режим используется
в локальном `dev-data`, чтобы неполный посторонний макет источника не отменял загрузку.

Production environment:

```dotenv
QF_ENV=production
QF_MUSHAF_SYNC_ENABLED=true
```

Celery Beat выполняет incremental sync ежедневно. Это укладывается в требование обновлять
кэш не реже одного раза в семь дней и не создаёт постоянную нагрузку на upstream.

## Публичный API Iqro

- `GET /api/v1/quran/foundation/mushafs`
- `GET /api/v1/quran/foundation/mushafs/{mushaf_id}/pages/{page_number}`

Ответ страницы содержит font mode, `rendering`, verse mapping и упорядоченные слова. Клиент
использует URL только из `rendering`, а слова группирует по `line_number`. В Quran DOM обязательно
устанавливаются `lang="ar"`, `dir="rtl"` и `translate="no"`. Шрифты не зеркалируются на нашем
сервере: они загружаются с официального CDN Quran.Foundation с CORS и долгим browser/CDN cache.
Дополнительные поля `native_rendering` и `native_assets` обратносуместимы. Пока полный набор
страниц не опубликован или source checksum изменился, status равен `not_ready`, а список assets
пуст. HTTP request никогда не запускает renderer.

Web reader показывает только доступные варианты из источника:
QCF V2 (`1`), KFGQPC Hafs (`5`) и цветной QCF V4 Tajweed (`19`). По умолчанию выбирается
KFGQPC, если он загружен. При пустом каталоге отображается сообщение об отсутствии данных.
Это варианты одного риваята:
все доступные production resources сейчас относятся к Hafs и отличаются способом рендеринга.
ID `11` не попадает в пользовательский список, пока `rendering.available=false`. Слова остаются
интерактивными: выбор или воспроизведение аята подсвечивает все его фрагменты на странице.

## Таджвид: правило по нажатию на слово

Источник — Content API `GET /content/api/v4/quran/verses/uthmani_tajweed`. Это Uthmani-текст QF,
в котором правила отмечены тегами `<tajweed class=…>`, а в конце аята стоит
`<span class=end>N</span>`. Ответ содержит все 6236 аятов и 17 классов правил. Справочник
названий, объяснений и цветов лежит в `modules/tajweed/rules.py`. Тексты ждут проверки
преподавателем: [docs/tajweed/rules-review.md](../../../docs/tajweed/rules-review.md).

Разметка привязывается к словам QF — тем же позициям `position_in_verse`, что у глифов шрифта
QCF V4 (Мусхаф 19). Юникод-тексты слов берутся из Мусхафа 4: у него те же `word_id`. Слова
сопоставляются по согласному скелету, потому что два текста QF местами по-разному ставят пробелы
(«بَعْدَمَا» / «بَعْدَ مَا»). Знаки ۞ и ۩ не считаются словами. Импорт останавливается без единой
записи, если:
- пришёл неизвестный класс или тег;
- нарушена вложенность тегов;
- номер в конце аята не совпадает с аятом;
- хотя бы одно слово не совпало с каноническим;
- набор аятов отличается от опубликованного Корана.

Перед импортом синхронизируйте Мусхафы QF 19 и 4 (`sync_quran_foundation_mushafs`).

```bash
python manage.py sync_quran_foundation_tajweed --dry-run
python manage.py sync_quran_foundation_tajweed
```

`--dry-run` скачивает и проверяет всё, но ничего не пишет. Без флага команда публикует новую
версию (`TajweedEditionVersion`) и делает её активной. Если контрольная сумма не изменилась,
команда ничего не меняет, поэтому её можно запускать повторно. Сухой прогон на данных QF
21.10.2026: 6236 аятов, 49 795 слов с правилами, 69 906 фрагментов. Импорт на production-сервер —
только по решению владельца.

Публичный API (кэш как у остальных каталогов: ETag, `public, max-age=300`, edge-кэш nginx):

- `GET /api/v1/quran/tajweed/rules` — справочник на ru/en/ar/tr, цвета палитры V4,
  `review_status`.
- `GET /api/v1/quran/tajweed/pages/{page}` — правила на странице Мусхафа 19: `rules` (для
  легенды) и `ayahs[].words[]` — только слова с правилами. У каждого слова `position` и `text`,
  у каждого правила `code`, `start`/`end` (смещения в `text`) и, если есть, `joins_previous`,
  `joins_next`, `variant`.
- `GET /api/v1/quran/tajweed/surahs/{surah}/ayahs/{ayah}` — то же для одного аята.

Пока разметка не импортирована, страницы и аяты отвечают 404. Сайт и приложение тогда не
показывают легенду, а нажатия работают как раньше.

Кнопка «Послушать фрагмент» берёт пословные тайминги чтеца из
`GET /api/v1/recitations/{id}/ayahs/{surah}/{ayah}`: поле `segment.words`, строки
`[позиция, start_ms, end_ms]` в треке суры. Импорт аудио QF сохраняет их из того же ответа
`chapter_recitations?segments=true`, который раньше брал только границы аятов. Контрольные суммы
таймингов от этого не меняются. Для уже опубликованных чтецов слова дописывает отдельная команда.
Она обновляет только треки, где границы аятов в QF совпадают с сохранёнными:

```bash
python manage.py backfill_quran_foundation_word_timings --dry-run
python manage.py backfill_quran_foundation_word_timings
```

## Аудио

Chapter-reciter и ayah-by-ayah — два разных каталога с несовместимыми source IDs. Полный
chapter-reciter каталог не скачивается как MP3. Iqro сохраняет metadata, проверенные
таймкоды, наблюдаемый origin size и официальный streaming URL:

```bash
python manage.py sync_quran_foundation_audio \
  --all-reciters --all-surahs --confirm-full-catalog --resume \
  --edition madani-hafs \
  --content-version 2026.08.25-production \
  --publish
```

Команда последовательная и возобновляемая. Каждый трек проверяется через bounded `HEAD`,
каждая сура обязана покрывать все канонические аяты. Полный проход 25 августа 2026 года
опубликовал 18/21 sources. `161`, `168` и `173` исключены из-за некорректных таймкодов.
В локальной БД сохранены 2 052 внешних streaming rendition и ни одного MP3/object blob.

Source ID обозначает конкретную запись/стиль поставщика, а не всегда отдельного человека.
Web-каталог объединяет IDs `1`/`2` как Абдуль-Басита и IDs `6`/`12` как аль-Хусари:
получается 16 карточек людей и 18 source records. Аватар и карточка показываются один раз,
а `mujawwad`/`murattal` или `muallim`/`murattal` остаются отдельными вариантами чтения.
Если повторный sync опубликовал несколько версий одного варианта, UI выбирает запись с самым
новым `published_at`.

Отдельный ayah-by-ayah каталог синхронизируется так:

```bash
python manage.py sync_quran_foundation_ayah_audio --edition madani-hafs
```

Production result: 12/12 sources, 1 368 групп по суре, 74 832 проверенных verse keys/URL,
24/24 CDN sample HEAD и 0 локальных MP3. Публичные endpoints:

- `GET /api/v1/quran-foundation/ayah-recitations`
- `GET /api/v1/quran-foundation/ayah-recitations/{source_id}/surahs/{surah}`

Данные привязаны к активной Hafs `QuranEditionVersion`; QF не помечает этот каталог qira'ah,
поэтому связывать его с Warsh/Qaloun/Shu'bah без отдельного подтверждения код не позволяет.

Применимые условия и фактическая production-проверка зафиксированы в
[`docs/sign-offs/quran-foundation-audio-license-decision-2026-08-25.md`](../../../docs/sign-offs/quran-foundation-audio-license-decision-2026-08-25.md).
