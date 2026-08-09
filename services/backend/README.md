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

## Подготовка страниц мусхафа

Проверка закреплённого PDF и атомарная подготовка lossless WebP-вариантов выполняются
отдельной management-командой. Она не импортирует данные в БД и не публикует контент.
Подробный операторский регламент: [docs/mushaf-page-assets.md](docs/mushaf-page-assets.md).
