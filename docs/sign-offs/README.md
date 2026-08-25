# Release sign-offs

Sign-off — это воспроизводимое письменное решение по конкретному immutable release, а не
устное «вроде работает». В Git не добавляются секреты, private API URLs, access tokens,
персональные контакты reviewer или конфиденциальная переписка.

## Web MVP package

1. Для официального page-art/text пакета отправить
   [запрос в King Fahd Complex](kfgqpc-production-files-request.md). Ответ и исходный upstream
   artifact сохраняются как закрытое release evidence; сторонний PDF из текущей `1.0.2` не
   становится production-safe от одного переименования.
2. Зафиксировать scope и технические риски в
   [fast-track release plan](../release/web-mvp-fast-track-2026-08-25.md).
3. Для Quran dataset создать новый
   [acceptance record](quran-content-acceptance-template.md). Исторический record
   [quran-content-acceptance.md](../quran-content-acceptance.md) показывает обнаруженный
   blocker: текущий
   `madani-hafs@1.0.2` заблокирован provenance page artwork и не является production candidate.
4. Для полного разрешённого каталога Quran.Foundation audio отправить
   [готовый запрос](quran-foundation-audio-confirmation-request.md) и сохранить безопасное
   резюме ответа в
   [license decision record](quran-foundation-audio-license-decision-template.md).
5. Каталог провайдера синхронизировать в `draft`: наличие записи в API не является автоматическим
   разрешением на публикацию и не доказывает совместимость с выбранным риваятом/мусхафом.
6. На каждого активируемого чтеца и вариант декламации скопировать и заполнить
   [religious/editorial review](quran-audio-editorial-review-template.md).
7. Product owner подписывает release decision только после зелёного CI/security, monitoring
   alert test, offsite backup evidence и production rollback smoke.

## Quran.Foundation: клиенты и домены

- Текущий Content API использует `client_credentials` только на общем backend. Web, native
  mobile и Telegram Mini App не получают QF secret и не регистрируются как Content API origins.
- Добавление отдельного first-party frontend origin само по себе не создаёт новый Content API
  credential: все клиенты получают только нужные данные через наш backend.
- Если позднее подключаются Quran.Foundation OAuth/User APIs, каждый точный redirect URI и
  post-logout URI добавляется отдельно в Developer Console; wildcard для этого не используется.
- Новые OAuth scopes запрашиваются в Developer Console до релиза. Если приложение участвует в
  Connected Apps review, новая platform link или иное material change также сообщается по их
  актуальной процедуре до публикации.

## Что означает отсутствие sign-off

- Quran dataset без полного acceptance record не активируется в production.
- Чтец без лицензионного и religious/editorial решения остаётся draft.
- Новый мусхаф/риваят без отдельной версии dataset, provenance и проверки соответствующего
  аудио остаётся draft; разные чтения не смешиваются внутри одной edition.
- Audio может быть полностью выключено, не блокируя text-only Web MVP, если Quran dataset сам
  имеет отдельную полную приёмку.
- Дедлайн не превращает пустое поле reviewer в разрешение.
