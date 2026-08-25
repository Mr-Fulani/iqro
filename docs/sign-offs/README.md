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
4. Для Quran.Foundation audio отправить
   [готовый запрос](quran-foundation-audio-confirmation-request.md) и сохранить безопасное
   резюме ответа в
   [license decision record](quran-foundation-audio-license-decision-template.md).
5. На каждого активируемого чтеца скопировать и заполнить
   [religious/editorial review](quran-audio-editorial-review-template.md).
6. Product owner подписывает release decision только после зелёного CI/security, monitoring
   alert test, offsite backup evidence и production rollback smoke.

## Что означает отсутствие sign-off

- Quran dataset без полного acceptance record не активируется в production.
- Чтец без лицензионного и religious/editorial решения остаётся draft.
- Audio может быть полностью выключено, не блокируя text-only Web MVP, если Quran dataset сам
  имеет отдельную полную приёмку.
- Дедлайн не превращает пустое поле reviewer в разрешение.
