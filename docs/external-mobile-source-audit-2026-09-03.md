# External Quran/mobile source audit — 2026-09-03

Проверены публичные репозитории `quran/quran.com-images` и все 18 репозиториев
пользователя `JMApps`. Цель аудита — отделить полезные продуктовые и технические идеи от
кода и контента, которые можно законно включить в backend, Android и iOS IQRO.

Это инженерный аудит, а не юридическое или религиозно-редакционное заключение.

## Зафиксированные версии

| Источник | Commit | Решение |
|---|---|---|
| `quran/quran.com-images` | `dbda5689691defc7e3b28314cc2d035ff027795c` | Только технический reference и независимый QA-oracle |
| `JMApps/quran` | `f08556a57d2af6c98baf8b5f2f854058925e17c4` | Только функциональный reference |
| `JMApps/mymushaf` | `1d040f68d284f8e6db515157f8425abfefd78df6` | Только функциональный reference |
| `JMApps/promus` | `2fa4daec0bed3062893a7dd769af2d2daedf1cc5` | Только функциональный reference |
| `JMApps/supplications_from_quran` | `bd4eef191bed5ac8ee64bb65dfd51477acc8206b` | Импортирован ограниченный сборник из 54 ду'а; см. provenance ниже |

Git SHA получены read-only. Для разрешённого ограниченного импорта сохранена только исходная
SQLite-база (`SHA-256 e8faad10345690ef6af1b16a493a601597f1245b1ea8812441f4efc667a14cce`),
а 54 закреплённых MP3 были однократно прочитаны для проверки Git blob SHA-1, размера и
вычисления SHA-256. Сами MP3 не входят в Git, Docker image или APK.

## Права и ограничения

### quran.com-images

README называет код «copyleft GPL», но в репозитории нет отдельного `LICENSE`/`COPYING`,
версии GPL и полного текста лицензии. Тот же README прямо отделяет права на код от прав на
604 page-specific TTF и созданные страницы: шрифты и страницы принадлежат King Fahd Quran
Complex.

Quran Foundation также уточняет, что Content Sync предоставляет metadata, page mapping и
positioned words, но не предоставляет дополнительных прав на Mushaf fonts/images. Его
offline-storage exception на эти assets не распространяется.

Следствие: нельзя переносить TTF, готовые страницы, Perl pipeline или хотлинкать внутренние
Quran.com assets до документального разрешения владельца конкретного asset-пакета.

### JMApps

GitHub metadata всех 18 репозиториев возвращает `license: null`; в профильных проектах нет
`LICENSE`/`COPYING`. Поэтому этот аудит не приписывает JMApps публичную лицензию и не делает
вывод о правах третьих лиц на отдельные переводы или записи.

3 сентября 2026 владелец проекта IQRO явно подтвердил, что проверил разрешение и разрешает
использовать материалы JMApps в IQRO. Это внутреннее основание зафиксировано в данных как
`rights_basis=iqro_owner_attested`; оно не подменяется выдуманным `license_url`, именем автора
перевода или чтеца. На этом основании импортирован только узкий, проверяемый набор
`supplications_from_quran`: 54 арабских текста, переводы EN/RU/TR и 54 audio metadata.
Каждое религиозное свидетельство остаётся `source_only` до редакционной проверки.

Остальные материалы JMApps продолжают использоваться только как описание поведения/UX,
пока для конкретного набора не появятся отдельные provenance, контрольные суммы, права и
редакционный review. Аттестация не является разрешением автоматически импортировать весь
профиль или неизвестные вложенные источники.

## Что найдено и что уже есть в IQRO

### Мусхаф и Quran search

`quran.com-images` генерирует PNG и glyph bounds из старых Madani page fonts. SQL содержит
page/line/ayah/word mapping, а также поля lemma/root/stem и word translations. JMApps/quran и
JMApps/mymushaf демонстрируют local SQLite, FTS, Juz/Hizb, закладки, историю и page-font
rendering.

IQRO уже имеет более безопасный production pipeline: immutable versions, WebP 480/900/1800,
SHA-256, manifests, 604 интерактивные страницы, ayah polygons, DPR-aware mobile cache,
атомарный offline installer, QF Mushaf metadata и native publication gate. Упаковка 604 TTF в
APK увеличила бы размер, не решила права и ухудшила бы управляемость обновлений.

Полезный будущий прирост: word-level hit map, morphology и полнотекстовый offline search —
только из лицензированного и редакционно проверенного источника. Старую разметку можно
использовать как независимый oracle для страниц 1, 2, 50, 255 и 604, не публикуя её.

### Du'a / Adhkar

JMApps/stronghold и JMApps/supplications_from_quran показывают хороший пользовательский набор:
поиск, аудио, повторения, источники/сноски, избранное, коллекции, copy/share и гибкие настройки
текста.

Backend IQRO уже хранит versioned Hisn al-Muslim, локализации RU/EN/AR/TR, источник,
evidence verification, audio assets, repetition count/label и синхронизируемое избранное.
Аудит обнаружил разрыв клиента: Flutter читал только первую cursor-страницу и игнорировал
`audio`, `repetition_label`, `evidence` и полные source metadata. Из-за page size 20 категория
с 24 элементами теряла четыре карточки.

Решение этого аудита — закрыть разрыв независимо написанным мобильным кодом поверх текущего
IQRO API: безопасно пройти все cursor-страницы, сохранить объединённый каталог для offline,
добавить streaming audio, практический счётчик повторов, copy/share и честное различение
`source_only` от `editorially_verified`.

После первой реализации контракт дополнительно подготовлен к нескольким сборникам: категории
содержат `collection` и `collection_version`, выбор категории передаёт оба идентификатора,
поиск выполняется сервером по всему каталогу, а `/dua/:id` загружает карточку без зависимости
от навигационного объекта в памяти. Мобильный клиент сверяет карту активных версий до и после
cursor-пагинации и не кеширует смешанный/неполный snapshot, если публикация изменилась между
страницами.

Новый второй сборник `supplications-from-quran` строится детерминированно из read-only SQLite
на закреплённом commit. Source lock содержит SHA-256 базы и каждого из 54 MP3, Git blob/tree
SHA и размеры; generated snapshot содержит ровно 54 записи и RU/EN/TR/AR. Миграция не
обращается к сети, публикует текст и pinned external audio URLs и не изменяет Hisn al-Muslim.
Пустые `author`, `reader_name` и `rights_url` намеренны: источник их достоверно не сообщает.

Аудио этого сборника остаётся streaming-функцией и не объявляется доступным для offline.
Переезд на собственный CDN допускается только отдельным publish-процессом с create-only
immutable upload и доказательством публичного CDN-контракта; непроверенный managed media не
может стать активным.

Обязательный profile-scoped этап выполнен перед включением remote pull. Мобильная SQLite-схема v4
хранит `owner_id` в позициях чтения, закладках, избранном, outbox, личном state и напоминаниях.
Запросы и отложенные ответы привязаны к исходной auth-сессии; guest→account handoff имеет durable recovery,
а logout сменяет installation credentials. Публичный каталог и тяжёлые offline-пакеты остаются общими.
Клиент теперь получает авторитетный snapshot избранных ду’а с сервера, накладывает ещё не отправленное
локальное намерение и сохраняет identity отозванной карточки, чтобы её можно было удалить из избранного.

### Prayer

JMApps/when_prayer полезен как checklist: Madhab, high-latitude rule, per-prayer minute
adjustments, Qibla, monthly schedule, local notifications и home widgets. База городов и
вложенные контентные базы не имеют provenance и не импортируются.

IQRO уже выполняет локальный расчёт и перепланирование уведомлений. Следующие независимые
приоритеты: UI ручных поправок, кыбла, месячный календарь и Android/iOS widgets.

## Матрица решений

| Возможность | Backend IQRO | Flutter IQRO | Решение |
|---|---|---|---|
| 604-page Mushaf, ayah hit map, offline | Готово | Готово | Не заменять старым font/PNG pipeline |
| Word-level hit map/morphology | QF positioned words частично готовы | Нет UI | Отдельный versioned слой после source/license audit |
| Quran FTS и Juz/Hizb/Rub navigation | Данные/API частично готовы | Неполная навигация/search | Реализовать независимо, без JMApps DB |
| Dua full pagination | API готов | Полный version-checked snapshot | Реализовано независимо |
| Dua audio/repetition/evidence/share | API готов; второй сборник импортирован с pinned external URLs | Streaming UI и metadata готовы | Реализовано; evidence пока `source_only`, offline закрыт |
| Несколько Dua collections и global search | Collection filter добавлен | Qualified category/search/deep link | Реализовано |
| Account-safe favorites pull | API готов | Owner-scoped snapshot + pending intent | Реализовано поверх SQLite v4 и auth-bound sync |
| Пользовательские Dua collections | В roadmap | Нет | Следующий versioned domain increment |
| Prayer advanced controls/widgets | Расчёт/напоминания готовы | Базовый UI | Следующий mobile increment |
| Tafsir corpus JMApps | Не найден | — | Использовать текущие versioned QF editions |
| Dictionary/quiz | Нет подтверждённого корпуса | Нет | P1 после отдельного rights/editorial audit |

## Границы текущего импорта и условия расширения

Owner attestation от 2026-09-03 покрывает текущий ограниченный импорт
`supplications_from_quran`, но не доказывает публичную лицензию. Для расширения на другие
репозитории или типы assets всё ещё нужно отдельно зафиксировать:

1. исходный код;
2. SQLite-контент и каждый перевод;
3. аудиозаписи;
4. шрифты и изображения;
5. изменение и встраивание в IQRO;
6. публикацию Android, iOS и web и раздачу через backend/CDN;
7. коммерческое использование, подписки, рекламу и пожертвования;
8. обязательную атрибуцию и возможность отзыва/withdrawal.

До выполнения этих условий другие репозитории не становятся content dependency IQRO.
Большие page-font/image наборы не импортируются из-за дублирования существующего versioned
Mushaf pipeline и размера; `JMApps/stronghold` не импортируется, потому что перекрывает уже
versioned Hisn; Quran SQLite/FTS не импортируются, потому что дублируют канонический backend
и не прошли отдельный provenance/editorial audit.

## Первичные ссылки

- https://github.com/quran/quran.com-images
- https://api-docs.quran.foundation/legal/developer-terms/
- https://api-docs.quran.foundation/legal/mushaf-fonts-and-images/
- https://github.com/JMApps
- https://github.com/JMApps/quran
- https://github.com/JMApps/mymushaf
- https://github.com/JMApps/stronghold
- https://github.com/JMApps/supplications_from_quran
- https://github.com/JMApps/when_prayer
- https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
