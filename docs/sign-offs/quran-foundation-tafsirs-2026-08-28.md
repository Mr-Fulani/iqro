# Quran.Foundation Tafsir staging decision — 2026-08-28

## Решение

Для Tafsir-раздела на staging выбраны все 13 production-ресурсов Quran.Foundation Content API
на активных языках интерфейса. Они не смешиваются со смысловыми переводами:

| Язык | Resource ID | Издание | Автор / организация | Slug |
|---|---:|---|---|---|
| العربية | `14` | Tafsir Ibn Kathir | Hafiz Ibn Kathir | `ar-tafsir-ibn-kathir` |
| العربية | `15` | Tafsir al-Tabari | Tabari | `ar-tafsir-al-tabari` |
| العربية | `16` | Tafsir Muyassar | المیسر | `ar-tafsir-muyassar` |
| العربية | `90` | Al-Qurtubi | Qurtubi | `ar-tafseer-al-qurtubi` |
| العربية | `91` | السعدي Al-Sa'di | Saddi | `ar-tafseer-al-saddi` |
| العربية | `93` | Al-Tafsir al-Wasit (Tantawi) | Waseet | `ar-tafsir-al-wasit` |
| العربية | `94` | Tafseer Al-Baghawi | Baghawy | `ar-tafsir-al-baghawi` |
| العربية | `925` | Arabic Tanweer Tafseer | Muhammad al-Tahir ibn Ashur | `arabic-tanweer-tafseer` |
| العربية | `926` | Arabic Jalalayn Tafseer | provider name fallback | `ar-tafsir-jalalayn` |
| English | `168` | Ma'arif al-Qur'an | Mufti Muhammad Shafi | `en-tafsir-maarif-ul-quran` |
| English | `169` | Ibn Kathir (Abridged) | Hafiz Ibn Kathir | `en-tafisr-ibn-kathir` |
| English | `817` | Tazkirul Quran | Maulana Wahid Uddin Khan | `tazkirul-quran-en` |
| Русский | `170` | Al-Sa'di | Saddi | `ru-tafseer-al-saddi` |

На дату проверки каталог провайдера содержит только один русский Tafsir (`170`) и не содержит
турецкого Tafsir. Каталоги фильтруются по текущему языку интерфейса: турецкий интерфейс не
подменяет Tafsir английским и показывает честное уведомление об отсутствии источника.

Это техническое решение разрешает закрытую staging-проверку. `QF_TAFSIR_SYNC_ENABLED`
по умолчанию выключен; включение в публичном production требует отдельного религиозного/
редакционного одобрения выбранных изданий.

## Проверенное provider-покрытие

Проверка выполнена 2026-08-28 через server-side production Content API без раскрытия
credentials или содержимого полных снимков:

| Resource ID | Provider records | Покрытие | Наблюдаемая особенность |
|---:|---:|---:|---|
| `16` | 5 278 | 6 236 аятов | часть записей объясняет диапазон из 2–14 аятов |
| `14` | 6 205 | 6 205 аятов | provider не содержит объяснение для 31 аята |
| `15` | 6 196 | 6 196 аятов | provider не содержит объяснение для 40 аятов |
| `90` | 6 236 | 6 236 аятов | одна строка использует корректную групповую ссылку |
| `91` | 6 177 | 6 177 аятов | provider не содержит объяснение для 59 аятов |
| `93` | 6 236 | 6 236 аятов | 128 строк используют групповые ссылки |
| `94` | 6 236 | 6 236 аятов | полное прямое покрытие |
| `925` | 3 923 | 6 236 аятов | авторские диапазоны покрывают несколько аятов |
| `926` | 6 236 | 6 236 аятов | полное прямое покрытие |
| `168` | 6 236 | 6 236 аятов | 3 199 строк используют групповые ссылки |
| `169` | 6 236 | 6 236 аятов | 4 340 строк ссылаются через `group_tafsir_id` на общий текст авторского диапазона |
| `170` | 6 236 | 6 236 аятов | 1 494 строки ссылаются через `group_tafsir_id` на общий текст авторского диапазона |
| `817` | 1 952 | 6 236 аятов | крупные авторские диапазоны покрывают несколько аятов |

Поэтому схема хранит каждую provider-строку и её диапазон `from–to`. Она не дедуплицирует
разные тексты с одинаковым групповым диапазоном. Если provider оставляет текст строки пустым,
`group_tafsir_id` обязан ссылаться на существующую непустую исходную строку с тем же диапазоном;
публичное представление получает текст этой строки, а исходное пустое значение сохраняется для
аудита. Для аята сначала выбирается точная строка; если её нет, используется охватывающий
авторский диапазон.

## Контракт хранения и обновления

- Каталог берётся из `GET /content/api/v4/resources/tafsirs`.
- Каждый разрешённый resource имеет отдельный Content Sync checkpoint и ежедневное обновление.
- Snapshot публикуется только при корректных verse IDs, отсутствии дублированных
  anchor-координат и разрешении каждого текста напрямую либо через корректный
  `group_tafsir_id`. Частичное provider-покрытие разрешено и явно фиксируется в
  `covered_ayah_count`; UI честно показывает отсутствие объяснения для конкретного аята.
- Версии immutable; повторное использование provider sequence с другим checksum блокируется.
- Исходная provider-разметка хранится для аудита, но публичный API отдаёт plain text и никогда
  не исполняет provider HTML.
- UI загружает Тафсир по требованию и открывает его отдельно для выбранного аята. Смысловой
  перевод и Тафсир имеют независимые переключатели.

## Права, атрибуция и ограничения

Применяются Quran.Foundation Developer Terms: контент показывается внутри полезного приложения,
не продаётся, не сублицензируется и не предоставляется как сырой публичный API dataset. В UI
показываются название, автор и атрибуция `Quran data provided by Quran Foundation.`

Официальные ссылки:

- [Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/)
- [Content Sync](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/)
- [Tafsir catalog](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/tafsirs/)
- [Tafsir records](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/tafsir/)
- [Resource snapshots](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-snapshot/)

Новые ресурсы не активируются только потому, что появились в каталоге. Для каждого следующего
источника отдельно проверяются язык, авторство, применимые права, структура, полнота и
редакционное решение.

## Настройки пользователя

Выбор перевода и Тафсира хранится в аккаунте отдельно для `ru`, `en`, `ar`, `tr`, имеет
optimistic revision и детерминированно объединяется при переходе гостя в зарегистрированный
аккаунт. Web storage остаётся безопасным fallback для пользователя без активной сессии; после
входа настройка переносится на backend и становится доступна будущим mobile/Telegram клиентам.
