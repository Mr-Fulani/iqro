# Quran.Foundation production content sync

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

## Команды

```bash
python manage.py migrate --noinput
python manage.py sync_quran_foundation_mushafs --force
python manage.py sync_quran_foundation_mushafs
```

`--force` нужен только для первого bootstrap или явного восстановления. Обычная команда
использует сохранённый token и получает только изменения. `RESOURCE_DELETE` удаляет локальную
копию; create/invalidate/row mutation заменяют только затронутый snapshot.

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
