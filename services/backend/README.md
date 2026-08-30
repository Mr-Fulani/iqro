# Quran Platform Backend

Backend использует Python 3.14, Django 6.1, Django REST Framework, PostgreSQL, Redis и Celery.

Репозиторий пока находится в pre-release стадии и не имеет общей постоянной базы данных,
поэтому стартовые миграции являются актуальным baseline. После первого shared/staging или
production deployment уже применённые миграции переписывать запрещено: любые изменения
схемы и перенос legacy-данных оформляются только новой миграцией. Если где-либо уже была
применена более ранняя версия baseline, deployment необходимо остановить и сначала
подготовить отдельную upgrade/data-migration.

## Локальная установка

```bash
cp .env.example .env
uv sync --all-groups
uv run python manage.py migrate
uv run python manage.py runserver
```

Для полного окружения используйте `compose.yaml`.

Полный набор тестов на настоящем PostgreSQL (включая конкурентную ротацию refresh)
запускается изолированным Docker target:

```bash
docker compose --profile test run --rm test
```

API гостевой авторизации, безопасной ротации токенов, позиции чтения, закладок и
offline-sync описан в [docs/auth-and-sync.md](docs/auth-and-sync.md). Актуальный контракт
доступен как OpenAPI 3.1 по `/api/schema`.

Passwordless-вход по подтверждённому email, HttpOnly browser-session и транзакционное
объединение гостевых данных описаны в
[docs/email-auth-and-guest-merge.md](docs/email-auth-and-guest-merge.md).
Управление устройствами, выборочный отзыв сессий и удаление аккаунта с повторной
email-проверкой и 7-дневным периодом отмены описаны в
[docs/auth-and-sync.md](docs/auth-and-sync.md#device-inventory-and-account-deletion).

MVP обратной связи с пользовательскими тикетами, безопасным reopen, SLA религиозного
контента и операторским workflow описан в [docs/feedback.md](docs/feedback.md). Вложения
на этом этапе намеренно не принимаются: небезопасного локального upload fallback нет.

Публичный каталог чтецов, version-pinned логические аудиотреки с bitrate/codec renditions,
проверенные таймкоды аятов, create-only S3 upload и immutable CDN evidence contract описаны в
[docs/audio-api.md](docs/audio-api.md).

Production Content Sync всех доступных Quran.Foundation Mushaf layout, локальный page cache,
checkpoint refresh и полный возобновляемый chapter-reciter import описаны в
[docs/quran-foundation-content.md](docs/quran-foundation-content.md).
Backend pipeline для заранее отрендеренных нативных страниц QCF V2, KFGQPC и QCF V4 Tajweed,
immutable CDN keys, fail-closed API и rollback описан в
[docs/qf-native-mushaf-pages.md](docs/qf-native-mushaf-pages.md).

Смысловые переводы хранятся в отдельном версионированном домене. Allowlist Content Sync
содержит все 15 проверенных English/Russian/Turkish translation-ресурсов активных языков сайта,
сверяет каждый snapshot с координатами опубликованного Корана и атомарно переключает активную
версию. Транслитерация и Tafsir-in-translation-mode не смешиваются со смысловыми переводами.
Операторский запуск: `python manage.py sync_quran_foundation_translations --force`.
Решение по источникам и правам: [docs/sign-offs/quran-foundation-translations-2026-08-28.md](docs/sign-offs/quran-foundation-translations-2026-08-28.md).

Тафсиры хранятся в независимом версионированном домене с авторскими диапазонами аятов.
Staging allowlist содержит все 13 Arabic/English/Russian Tafsir-ресурсов провайдера; частичное
покрытие хранится явно и не подменяется текстом другого языка.
Операторский запуск: `python manage.py sync_quran_foundation_tafsirs --force`.
Техническое решение и production-gate: [docs/sign-offs/quran-foundation-tafsirs-2026-08-28.md](docs/sign-offs/quran-foundation-tafsirs-2026-08-28.md).

Версионированный каталог методов намаза, stateless-расчёт одного дня, high-latitude/polar
правила, pinned tzdata и privacy contract для координат описаны в
[docs/prayer-api.md](docs/prayer-api.md).

Синхронизируемый профиль намаза, строгие правила локальных prayer/Quran reminders,
optimistic concurrency, минимизированные tombstones, retention и контракты планирования
для Flutter/Web/Telegram Mini App описаны в
[docs/prayer-profile-and-reminders.md](docs/prayer-profile-and-reminders.md).

Ежедневная норма чтения, ручные и автоматические сессии, серии дней и план чтения после
пяти намазов описаны в [docs/reading-habit.md](docs/reading-habit.md).

## Подготовка страниц мусхафа

Проверка закреплённого PDF и атомарная подготовка lossless WebP-вариантов выполняются
отдельной management-командой. Она не импортирует данные в БД и не публикует контент.
Подробный операторский регламент: [docs/mushaf-page-assets.md](docs/mushaf-page-assets.md).

Для локального page-only просмотра полный результат можно разместить внутри `MEDIA_ROOT`,
проверить повторно, зарегистрировать в БД и активировать:

```bash
uv run python manage.py prepare_mushaf_pages \
  ../../quran-hafs-mushaf.pdf \
  --output media/quran/madani-hafs/1.0.0 \
  --variant-width 900

# Для другого издания параметры PDF и edition metadata берутся из asset build-spec:
uv run python manage.py prepare_mushaf_pages \
  /path/to/warsh-mushaf.pdf \
  --spec /path/to/warsh-mushaf-asset-spec.json \
  --output media/quran/madani-warsh/1.0.0 \
  --variant-width 900

uv run python manage.py publish_mushaf_pages \
  media/quran/madani-hafs/1.0.0/manifest.json \
  --activate
```

В production к команде обязательно добавляется `--upload`, чтобы до записи в БД
создать/сверить immutable S3 objects:

```bash
uv run python manage.py publish_mushaf_pages \
  media/quran/madani-hafs/1.0.0/manifest.json \
  --upload --activate
```

Команда публикации идемпотентна и перед записью в БД сверяет `manifest.sha256`, наличие,
размер и SHA-256 каждой заявленной страницы. Manifest schema v2 переносит edition/riwayah и
количество страниц из проверенной asset spec, поэтому публикация также не привязана к Hafs или
604 страницам. Page-only версия не добавляет канонический текст,
границы джузов или интерактивные координаты аятов; их по-прежнему следует импортировать
отдельным проверенным Quran dataset.

## Полный Quran dataset

Сборщик `build_quran_dataset` объединяет закреплённый нормализованный Quran corpus,
ayah-polygons и подготовленные WebP-страницы. Код не привязан к одному риваяту: edition code,
riwayah, версии, ожидаемые количества, SHA-256 исходников, page geometry, object-key prefix и
provenance задаются отдельной проверяемой build-spec. Без `--spec` сохраняется совместимый
профиль текущего `madani-hafs@1.0.2`; его точные commits, SHA и лицензии записаны в
[docs/quran-sources.lock.json](docs/quran-sources.lock.json).

```bash
uv run python manage.py build_quran_dataset \
  /path/to/quran-dataset/data/quran.json \
  /path/to/quran-svg/mushafs/hafs/kfqc/json \
  media/quran/madani-hafs/1.0.0/manifest.json \
  media/quran/datasets/madani-hafs-1.0.2

# Любое другое издание/риваят с собственными закреплёнными источниками:
uv run python manage.py build_quran_dataset \
  /path/to/normalized-warsh-quran.json \
  /path/to/warsh/page-regions \
  /path/to/warsh/page-assets/manifest.json \
  media/quran/datasets/madani-warsh-1.0.0 \
  --spec /path/to/madani-warsh-build-spec.json

uv run python manage.py import_quran_dataset \
  media/quran/datasets/madani-hafs-1.0.2

uv run python manage.py publish_quran_version \
  --edition madani-hafs --content-version 1.0.2 --activate

uv run python manage.py audit_quran_regions \
  media/quran/datasets/madani-hafs-1.0.2
```

Импорт создаёт только draft. Отдельная команда публикации повторно проверяет фактические
количества сур, страниц, джузов, хизбов и четвертей, покрытие каждого аята регионом и
наличие source manifest.

Формат и правила build-spec описаны в
[docs/quran-dataset-build-spec.md](docs/quran-dataset-build-spec.md). Поддержка формата не
означает, что официальные файлы Warsh/Qaloun/Shu'bah уже получены или разрешены к публикации:
для реального кандидата всё равно нужны закреплённые исходники, права и три sign-off.
