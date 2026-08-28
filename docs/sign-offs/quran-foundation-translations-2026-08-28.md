# Quran.Foundation translations source decision — 2026-08-28

## Решение

Для web-релиза используются все 15 смысловых translation-ресурсов Quran.Foundation
Content API на активных языках интерфейса (`en`, `ru`, `tr`):

| Язык | Resource ID | Издание | Автор / организация | Slug |
|---|---:|---|---|---|
| English | `19` | M. Pickthall | Mohammed Marmaduke William Pickthall | `quran.en.pickthall` |
| English | `20` | Saheeh International | Saheeh International | `en-sahih-international` |
| English | `22` | A. Yusuf Ali | Abdullah Yusuf Ali | `quran.en.yusufali` |
| English | `84` | T. Usmani | Mufti Taqi Usmani | `en-taqi-usmani` |
| English | `85` | M.A.S. Abdel Haleem | Abdul Haleem | `en-haleem` |
| English | `95` | A. Maududi (Tafhim commentary) | Sayyid Abul Ala Maududi | `en-al-maududi` |
| English | `203` | Al-Hilali & Khan | M. al-Hilali & M. Muhsin Khan | generated from resource ID |
| Русский | `45` | Elmir Kuliev | Elmir Kuliev | `quran.ru.kuliev` |
| Русский | `78` | Ministry of Awqaf, Egypt | Ministry of Awqaf, Egypt | `ru-ministry-of-awqaf` |
| Русский | `79` | Abu Adel | Abu Adel | `ru-abu-adel` |
| Türkçe | `52` | Elmalili Hamdi Yazir | Elmalili Hamdi Yazir | `tr-hamdi` |
| Türkçe | `77` | Turkish Translation (Diyanet) | Diyanet Isleri | `quran.tr.diyanet` |
| Türkçe | `112` | Shaban Britch | Shaban Britch | generated from resource ID |
| Türkçe | `124` | Muslim Shahin | Muslim Shahin | generated from resource ID |
| Türkçe | `210` | Dar Al-Salam Center | Dar Al-Salam Center | generated from resource ID |

Арабский resource `1014` («Tafsir Al-Muyasser in Translation Mode») не публикуется как
смысловой перевод: он доступен в отдельном Tafsir-разделе через настоящий resource `16`.
English resource `57` является транслитерацией, а не смысловым переводом, поэтому будет
подключён позже отдельной функцией чтения, но не смешивается с переводами.

Каталог UI всегда запрашивается с текущей локалью. Поэтому русскоязычный интерфейс показывает
только три русских перевода, английский — семь английских, турецкий — пять турецких; в арабском
интерфейсе смысловой перевод выключен, а объяснения находятся в отдельном Tafsir-блоке.

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

## Ограничения и правила интерфейса

- Выбор перевода и Тафсира синхронизируется с аккаунтом через revisioned preference contract,
  отдельно для каждого языка интерфейса. Web storage остаётся fallback без активной сессии.
  Для арабского языка смысловой перевод по умолчанию выключен, а отдельный арабский Тафсир
  доступен по запросу пользователя.
- Сноски переводчика выводятся под соответствующим аятом раскрываемым нумерованным списком.
  Номера `[1]`, `[2]` в тексте соответствуют порядку пояснений в этом списке.
- Перевод не подвергается автоматическому машинному переводу. Блоки UI помечены
  `translate="no"`.
- Новые provider-ресурсы не включаются автоматически. Allowlist обновляется только после
  проверки типа ресурса, языка, полноты, атрибуции и технического staging-аудита.
