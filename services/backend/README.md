# Quran Platform Backend

Backend использует Python 3.14, Django 6.1, Django REST Framework, PostgreSQL, Redis и Celery.

Применённые миграции не переписываются: изменения схемы и перенос существующих данных
оформляются новой миграцией, в том числе на локальных машинах команды.

## Локальная установка

Основной путь — из корня репозитория:

```bash
make dev-init
# Заполнить services/backend/.env ключами Quran.Foundation
make up
```

Смотрите [полную инструкцию](../../docs/local-development.md).
Корневой Compose загружает `.env` в backend. При запуске Python непосредственно на хосте
переменные надо передать процессу отдельно; Django не читает этот файл автоматически.
`uv` — менеджер Python и зависимостей; он не нужен на хосте для основного Docker-сценария.
Для локальных проверок: `uv sync --frozen --all-groups`, `uv run pytest`.

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
Решение по источникам и правам: [docs/sign-offs/quran-foundation-translations-2026-08-28.md](../../docs/sign-offs/quran-foundation-translations-2026-08-28.md).

Тафсиры хранятся в независимом версионированном домене с авторскими диапазонами аятов.
Staging allowlist содержит все 13 Arabic/English/Russian Tafsir-ресурсов провайдера; частичное
покрытие хранится явно и не подменяется текстом другого языка.
Операторский запуск: `python manage.py sync_quran_foundation_tafsirs --force`.
Техническое решение и production-gate: [docs/sign-offs/quran-foundation-tafsirs-2026-08-28.md](../../docs/sign-offs/quran-foundation-tafsirs-2026-08-28.md).

Версионированный каталог методов намаза, stateless-расчёт одного дня, high-latitude/polar
правила, pinned tzdata и privacy contract для координат описаны в
[docs/prayer-api.md](docs/prayer-api.md).

Синхронизируемый профиль намаза, строгие правила локальных prayer/Quran reminders,
optimistic concurrency, минимизированные tombstones, retention и контракты планирования
для Flutter/Web/Telegram Mini App описаны в
[docs/prayer-profile-and-reminders.md](docs/prayer-profile-and-reminders.md).

Ежедневная норма чтения, ручные и автоматические сессии, серии дней и план чтения после
пяти намазов описаны в [docs/reading-habit.md](docs/reading-habit.md).

## Данные Корана и Мусхафов

Канонические `MushafPage` сохраняют номера и идентификаторы, на которые ссылается прогресс
чтения. `AyahPageMapping` хранит соответствие аятов страницам независимо от изображений.
Миграция 0007 копирует старые связи без изменения UUID страниц, аятов и пользовательских записей.

`sync_quran_foundation_mushafs` загружает слова и структуру страниц из QF.
`import_quran_corpus <путь>` проверяет закреплённый SHA-256 текста Tanzil и создаёт
канонический корпус со связями страниц QF 5. Повторный импорт сохраняет UUID; при
несовместимости существующего текста или нумерации он останавливается без замены данных.

Web и Flutter отображают все 13 макетов из `foundation/mushafs`. Контракт `rendering.version=2`
возвращает режим страницы, WOFF2/TTF для клиента или URL официальных изображений слов,
а также безопасные цветовые фрагменты таджвида. `page-index` связывает аят со всеми его
страницами в выбранном макете; номера могут отличаться от канонических 604 страниц.
`make up` загружает весь каталог и проверяет полноту страниц/слов. Секреты QF не выдаются
клиентам. Подробности: [каталог и отображение](../../docs/quran-foundation-mushafs.md).

`MushafRenditionRelease`, WebP и uploader остаются необязательным путём для ранее
опубликованных растровых наборов. Автозапуск больше не требует их генерации.
Готовый канонический корпус и пользовательские UUID сохраняются.

Локальные изображения публикуются в `MEDIA_ROOT` через отдельный uploader с проверкой
SHA-256 и запретом перезаписи. Этот режим разрешён только при local settings и DEBUG.
Производственная публикация сохраняет существующие проверки источника и объектного хранилища.

PDF-подготовка и её API выведены из эксплуатации. Старые `editions/{code}/pages/{n}`
и `editions/{code}/offline-manifest` отвечают 410; клиенты используют
`foundation/mushafs` и необязательные `mushaf-renditions`. Старые поля БД и импорт ранее проверенных dataset сохраняются
для совместимости и миграции, но не участвуют в выборе/отображении Мусхафа.
