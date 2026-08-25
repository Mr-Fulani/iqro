# Quran.Foundation production content decision

Дата проверки: 25 августа 2026 года.

## Решение

**STANDARD TERMS SUFFICIENT** для server-side Content API и first-party показа/streaming в
Iqro Web, будущих iOS/Android клиентах и Telegram Mini App.

Отдельное письмо или коммерческая лицензия не являются production gate, пока Iqro:

- показывает QF Content только как часть пользовательского опыта Iqro;
- не продаёт и не распространяет сырой QF Content как dataset, feed, API или content package;
- не копирует QF audio в R2/VPS и не включает offline download;
- хранит credentials только на backend;
- показывает обязательную атрибуцию и применяет source-specific условия;
- обновляет локальный кэш не реже установленного Terms срока.

Основание: [Quran.Foundation Developer Terms](https://api-docs.quran.foundation/legal/developer-terms/),
версия с датой обновления 18 августа 2026 года, и официальный
[Content Sync contract](https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/).

## Проверенная production-интеграция

- OAuth Client Credentials production token получен без раскрытия credentials.
- Доступны 21 chapter-reciter и 12 ayah-by-ayah recitation resources.
- Bounded `HEAD`/startup/seek проверка source `7`, сура 1: delivery успешен, HTTP `200/206`,
  Range работает; provider metadata `839808` bytes устарела относительно origin `793327`
  bytes. Импортёр использует наблюдаемый `Content-Length`.
- Пилот с сурой 1 выполнен для всего chapter-reciter каталога: 20/21 прошли проверку.
- Полная проверка всех 114 сур опубликовала 18/21 sources: 2 052 surah tracks, 112 248
  ayah segments, 2 052 external renditions и ни одного локального audio object.
- Sources `161`, `168` и `173` исключены fail-closed из-за некорректных upstream-таймкодов;
  точные безопасные ошибки сохранены в
  [full-catalog evidence](../capacity/quran-foundation-production-catalog-2026-08-25.md).
- QF audio сохраняется только как внешний streaming URL; `offline_download_allowed=false`.
- Content Sync вернул Mushaf IDs `1`, `5`, `11`, `19`, все с qira'ah `Hafs`.
- Полный локальный Mushaf bootstrap: 4 resources, 2 416 страниц, 334 660 позиционированных
  слов, checkpoint sequence `1399`; повторный incremental sync не скачал snapshot заново.

## Когда потребуется отдельное согласование

До реализации любого из пунктов необходимо повторно проверить Terms и при необходимости
отправить [подготовленный запрос](quran-foundation-audio-confirmation-request.md):

- rehosting или преобразование QF audio;
- offline redistribution;
- публичный third-party content API/feed/dataset;
- продажа или сублицензирование сырого QF Content;
- использование ресурса с отдельными source-specific ограничениями.

Этот record не разрешает перечисленные нестандартные сценарии и не отменяет техническую
проверку риваята, полноты сур, таймкодов и доступности origin для каждой публикации.
