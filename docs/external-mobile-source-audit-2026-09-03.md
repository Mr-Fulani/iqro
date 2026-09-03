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

SHA получены через read-only `git ls-remote`; внешние репозитории и бинарные assets локально
не клонировались.

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
`LICENSE`/`COPYING`. Публичные сообщения автора говорят, что приложения бесплатны и исходный
код открыт на GitHub, но не формулируют право изменять и распространять код, SQLite-базы,
переводы, аудио, шрифты и изображения как часть другого продукта.

Следствие: до отдельного письменного разрешения материалы JMApps используются только как
описание поведения/UX. Реализация IQRO пишется независимо поверх уже проверенных собственных
моделей и источников.

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

Автоматический remote pull избранного в этот этап не входит: локальные персональные таблицы
мобильного клиента пока не разделены по профилям. До schema migration с отдельным
`profile_scope_id` такой pull мог бы показать или перезаписать данные предыдущего аккаунта.
Текущая локальная работа избранного и существующая outbox-доставка сохранены без расширения
этого риска; profile-scoped storage и привязка sync-запросов к исходной auth-сессии должны
быть отдельным обязательным этапом до поддержки переключения аккаунтов.

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
| Dua full pagination | API готов | Дефект: только первая страница | Исправить немедленно |
| Dua audio/repetition/evidence/share | API готов | Поля отбрасываются | Реализовать немедленно |
| Account-safe favorites pull | API готов | Нет profile partition | Сначала schema migration и auth-bound sync |
| Пользовательские Dua collections | В roadmap | Нет | Следующий versioned domain increment |
| Prayer advanced controls/widgets | Расчёт/напоминания готовы | Базовый UI | Следующий mobile increment |
| Tafsir corpus JMApps | Не найден | — | Использовать текущие versioned QF editions |
| Dictionary/quiz | Нет подтверждённого корпуса | Нет | P1 после отдельного rights/editorial audit |

## Условия возможного будущего импорта JMApps

Нужно отдельное письменное разрешение, явно покрывающее:

1. исходный код;
2. SQLite-контент и каждый перевод;
3. аудиозаписи;
4. шрифты и изображения;
5. изменение и встраивание в IQRO;
6. публикацию Android, iOS и web и раздачу через backend/CDN;
7. коммерческое использование, подписки, рекламу и пожертвования;
8. обязательную атрибуцию и возможность отзыва/withdrawal.

До выполнения этих условий репозитории не являются content dependency IQRO.

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
