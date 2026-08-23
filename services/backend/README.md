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

MVP обратной связи с пользовательскими тикетами, безопасным reopen, SLA религиозного
контента и операторским workflow описан в [docs/feedback.md](docs/feedback.md). Вложения
на этом этапе намеренно не принимаются: небезопасного локального upload fallback нет.

Публичный каталог чтецов, version-pinned аудиотреки, проверенные таймкоды аятов,
immutable CDN contract и безопасная загрузка отдельной суры описаны в
[docs/audio-api.md](docs/audio-api.md).

Версионированный каталог методов намаза, stateless-расчёт одного дня, high-latitude/polar
правила, pinned tzdata и privacy contract для координат описаны в
[docs/prayer-api.md](docs/prayer-api.md).

Синхронизируемый профиль намаза, строгие правила локальных prayer/Quran reminders,
optimistic concurrency, минимизированные tombstones, retention и контракты планирования
для Flutter/Web/Telegram Mini App описаны в
[docs/prayer-profile-and-reminders.md](docs/prayer-profile-and-reminders.md).

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

uv run python manage.py publish_mushaf_pages \
  media/quran/madani-hafs/1.0.0/manifest.json \
  --activate
```

Команда публикации идемпотентна и перед записью в БД сверяет `manifest.sha256`, наличие,
размер и SHA-256 каждой из 604 страниц. Page-only версия не добавляет канонический текст,
границы джузов или интерактивные координаты аятов; их по-прежнему следует импортировать
отдельным проверенным Quran dataset.

## Полный Quran dataset

Сборщик `build_quran_dataset` объединяет закреплённый Tanzil Uthmani corpus, KFQC
ayah-polygons и подготовленные WebP-страницы. Он принимает только известные SHA-256,
проверяет покрытие всех 6236 аятов, 60 хизбов и 240 четвертей хизба и переводит нативные
координаты KFQC в координаты страницы PDF. Точные commits, SHA и лицензии записаны в
[docs/quran-sources.lock.json](docs/quran-sources.lock.json).

```bash
uv run python manage.py build_quran_dataset \
  /path/to/quran-dataset/data/quran.json \
  /path/to/quran-svg/mushafs/hafs/kfqc/json \
  media/quran/madani-hafs/1.0.0/manifest.json \
  media/quran/datasets/madani-hafs-1.0.2

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
