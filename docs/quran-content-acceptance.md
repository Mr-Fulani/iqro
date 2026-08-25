# Quran content acceptance record — madani-hafs@1.0.2

Статус: **release blocked до заполнения внешних sign-off**

Дата технической подготовки: 23 августа 2026 года

Этот документ является release gate, а не декларацией религиозной или юридической
приёмки. Незаполненное поле reviewer блокирует публичную активацию версии.

## Неизменяемый артефакт

- Edition: `madani-hafs`
- Version: `1.0.2`
- Dataset schema: `2`
- Aggregate SHA-256: `66cc6b136ed3a8c43130278e07ad55e1f68af6064395d034dbdf765ed043c081`
- 114 сур, 6 236 аятов, 604 страницы, 30 джузов, 60 хизбов, 240 четвертей хизба
- 12 346 polygon segments; 4 441 многосегментный аят
- Source lock: [quran-sources.lock.json](../services/backend/docs/quran-sources.lock.json)
- Dataset manifest: `services/backend/media/quran/datasets/madani-hafs-1.0.2/manifest.json`

## Технические доказательства

| Проверка | Результат | Дата |
|---|---|---|
| Source commits и исходные SHA-256 | Пройдено | 2026-08-23 |
| Aggregate/per-file checksums | Пройдено | 2026-08-23 |
| 114/6236/604/30/60/240 | Пройдено | 2026-08-23 |
| Region audit всех 604 страниц | Пройдено: 12 346 сегментов | 2026-08-23 |
| Viewport matrix 375/768/1440 px | Пройдено в Playwright | 2026-08-23 |
| Backend suite | 463 passed, 6 skipped; coverage 84,99% | 2026-08-23 |
| Web lint/typecheck/build/E2E | Пройдено; 6 E2E cases | 2026-08-23 |

## Техническая подготовка staging — не sign-off

25 августа 2026 года на `staging.iqro.forum` выполнена подготовка без публичной активации:

- pre-import и post-import PostgreSQL backup созданы и прошли checksum/archive verification;
- `madani-hafs@1.0.2` повторно прошёл checksum validation внутри staging backend и импортирован
  одной транзакцией со статусом `draft`;
- staging БД содержит 114 сур, 6 236 аятов, 604 страницы и 12 346 региональных сегментов;
- полный publication validator прошёл, но `active_version` намеренно остаётся пустым, а
  публичный `GET /api/v1/quran/editions` возвращает `[]`;
- в приватный каталог VPS переданы 604 WebP; проверка всех asset SHA-256 прошла с manifest
  `2fb661457c5a1aba768e42fe731c814a42113057b0acacbe9ad6e619703ad6b2`;
- загрузка этих страниц в публичный R2 bucket и команды publish/activate намеренно не
  выполнялись до трёх внешних sign-off ниже.

Этот результат доказывает техническую готовность и rollback path, но не является религиозной,
юридической или продуктовой приёмкой.

Повторяемая команда геометрического gate:

```bash
cd services/backend
uv run python manage.py audit_quran_regions \
  media/quran/datasets/madani-hafs-1.0.2
```

## Обязательная ручная проверка

Reviewer должен сверять изображение, номер страницы, текст, номер аята и выбранную область
минимум на следующих классах страниц:

- страницы 1–2: специальная геометрия вступительных страниц;
- страница 128, аят 6:2: ранее зарегистрированный многосегментный regression case;
- длинный аят и переход между строками;
- граница суры, джуза, хизба и четверти хизба;
- последняя страница 604;
- mobile, tablet и desktop viewport.

Дополнительные замечания reviewer фиксируются ticket'ами категории `quran_content`; версия
не редактируется на месте, исправление выпускается только новой immutable-версией.

## Sign-off

| Gate | Reviewer | Дата | Решение | Evidence/ticket |
|---|---|---|---|---|
| Технический | Codex automated verification | 2026-08-23 | Готово | Этот record и CI output |
| Религиозно-редакционный | — | — | **Ожидается** | — |
| Лицензия/юридический | — | — | **Ожидается** | — |
| Product release owner | — | — | **Ожидается** | — |

## Активация и rollback

Активация разрешена только после трёх внешних sign-off:

```bash
cd services/backend
uv run python manage.py import_quran_dataset \
  media/quran/datasets/madani-hafs-1.0.2
uv run python manage.py publish_quran_version \
  --edition madani-hafs --content-version 1.0.2 --activate
```

Rollback не изменяет данные и возвращает указатель edition на ранее опубликованную версию:

```bash
cd services/backend
uv run python manage.py publish_quran_version \
  --edition madani-hafs --content-version 1.0.1 --activate
```

После rollback CDN/API caches должны быть инвалидированы по content version, а причина и
ticket записаны в release journal.
