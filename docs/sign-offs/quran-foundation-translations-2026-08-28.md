# Quran.Foundation translations source decision — 2026-08-28

## Решение

Для первого web-релиза смысловых переводов используются три production-ресурса
Quran.Foundation Content API:

| Язык | Resource ID | Издание | Автор / организация | Slug |
|---|---:|---|---|---|
| English | `20` | Saheeh International | Saheeh International | `en-sahih-international` |
| Русский | `45` | Elmir Kuliev | Elmir Kuliev | `quran.ru.kuliev` |
| Türkçe | `77` | Turkish Translation (Diyanet) | Diyanet Isleri | `quran.tr.diyanet` |

Арабский resource `1014` («Tafsir Al-Muyasser in Translation Mode») не публикуется как
смысловой перевод. Он относится к будущему отдельному домену тафсира и потребует собственного
редакционного решения.

## Контракт хранения и обновления

- Каталог берётся из `GET /content/api/v4/resources/translations`.
- Каждый ресурс синхронизируется отдельным Content Sync checkpoint. Это также обходит
  наблюдаемое 2026-08-28 production-поведение, при котором multi-ID translation filter
  возвращал только первый ресурс.
- Полный snapshot обязан в точности совпасть с множеством координат активного опубликованного
  арабского Корана. Неполный, дублированный или посторонний набор не публикуется.
- Новая версия неизменяема; активный указатель переключается атомарно. Ежедневный job заметно
  короче предельного семидневного окна обновления.
- Исходная provider-разметка хранится только для проверки целостности. Публичный API отдаёт
  очищенный plain text и структурированные footnotes, поэтому UI не исполняет provider HTML.

## Права и атрибуция

Quran.Foundation Developer Terms разрешают показывать Quran content внутри полезного
приложения, но запрещают продавать, сублицензировать или распространять сырой API dataset.
При использовании Content Sync изменения должны применяться не реже одного раза в семь дней.

Каждое издание показывает собственное название и автора, а также обязательную атрибуцию:
`Quran data provided by Quran Foundation.`

Официальные ссылки:

- [Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/)
- [Content Sync](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/)
- [Translation catalog](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/translations/)
- [Translation snapshots](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-snapshot/)

## Ограничения первой версии

- Выбор перевода сохраняется device-local в web storage. Account-level preference и sync между
  web/mobile/Telegram добавляются после общего client preference contract. Предпочтения разделены
  по языкам интерфейса; для арабского языка перевод по умолчанию выключен, поскольку арабское
  объяснение относится к будущему отдельному разделу тафсира.
- Сноски переводчика выводятся под соответствующим аятом раскрываемым нумерованным списком.
  Номера `[1]`, `[2]` в тексте соответствуют порядку пояснений в этом списке.
- Перевод не подвергается автоматическому машинному переводу. Блоки UI помечены
  `translate="no"`.
- Публикация дополнительных переводов требует проверки прав, качества, атрибуции и языка;
  наличие ресурса в provider catalog само по себе не означает автоматическую публикацию.
