# Предзагрузка Мусхафа и мобильные свайпы: staging, 9 сентября 2026

## Изменения и версия

Ветка `codex/web-reader-preload`, commit `618ccecf2a735176c5dfd970456fed66955c0ce6`.
Merge в `codex/mobile-ui-prototype`: `08b4bdc92197dbe95e6e57c22730f9626adb20e6`.
Дерево `services/web` после merge совпало с проверенной веткой: `d85ae8bc9920044dfae106b90940a0c577052f57`.

Изменены только 13 файлов фронтенда: предзагрузка двух соседних страниц с обеих сторон,
декодирование изображений, переиспользование шрифтов, короткие свайпы с визуальным откликом,
сворачиваемые настройки в landscape и отдельная кнопка скрытия панели. Сервер, контракты API,
аудиоплеер, авторизация, данные Корана и нативный клиент этим релизом не изменялись.

45/45 браузерных сценариев прошли. После последней корректировки раскрытия настроек
проверены ещё 10 выбранных сценариев: 9 сразу и один после уточнения тестового ожидания
начального закрытого состояния. Прошли 4/4 модульных теста кэша, lint, TypeScript,
production build, CSS integrity (2 чанка, 116 740 байт) и diff check.
Подробности: `services/web/docs/mobile-presentation-review.md`.

## Подготовка и резервная копия

Среда: `https://staging.iqro.forum`, `/opt/quran` на `162.55.35.8`.
Релиз: `/opt/quran/releases/web-reader-preload-20260909/`.

```text
source.tar.gz SHA256=e2b14abcf05552820846c60882bb88dc47316c1448e14c47c8e99d41ed287c34
BACKUP_FILE=/backups/quran_staging_20260909T064535Z.dump
backup SHA256=887f4f9f9113227e4667d838198cb3749004ef1786cec73b1578811e19fe0b04
```

Архив содержит только `services/web` из merge commit. Перед сборкой передача завершилась
и SHA256 совпал. Backup прошёл checksum и `pg_restore --list`. Runtime override
`BACKUP_RETENTION_DAYS=0` сохранил все прежние копии; серверный backup.sh предварительно
сверен с локальным. Операции очистки не выполнялись.

## Rollout

```text
WEB_IMAGE=quran-platform-web:staging-08b4bdc
Image ID=sha256:9ee435751b1eb6f3c59a78da49cac5b033a721cfce6e94ba7f46a465ee318996
revision=08b4bdc92197dbe95e6e57c22730f9626adb20e6
previous WEB_IMAGE=quran-platform-web:staging-84ff100
```

В 06:55 UTC обновлён только web через production/staging/budget Compose overlays,
с `--no-deps --no-build --detach --wait`. Web healthy. ID и образы остальных восьми
работающих сервисов совпали со снимком перед релизом. Runtime budget verification прошёл.

После успешных HTTP-проверок обновлены веб-исходники и `.deployed-commit`.
Прежний образ, исходники и marker сохранены в материалах релиза вместе с журналами.
Для отката работающего сервиса выбрать `WEB_IMAGE=quran-platform-web:staging-84ff100`
тем же точечным Compose-вызовом. Миграций нет.

## Проверки после запуска

- Readiness: status=ok, database/cache/throttling=true.
- HTTP 200: `/ru`, `/ru/quran`, `/ru/dua`, `/ru/audio`, `/ar/quran`.
- В браузере при 390×844 выполнены переходы 1 → 2 → 3. Страница 3 уже имела готовое
  изображение (`complete=true`), загрузочных заглушек не было, scrollWidth=390.
- При 844×390 панель сворачивается до одной кнопки, освобождая страницу для чтения.
- Подробные настройки в landscape закрываются по summary: open=false,
  summary display=flex, scrollWidth=844 при viewport=844.
- Возврат в читалку и переходы 3 → 2 → 1 прошли; исходный размер браузера восстановлен.
- Localhost пересобран и оставлен на порту 3101 с ограниченными API-фикстурами.

Настоящий Safari/iOS в этот прогон не входил. Это обновление существующего staging.
