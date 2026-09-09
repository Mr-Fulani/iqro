# Выход из читалки и анимация страниц: staging, 9 сентября 2026

Ветка `codex/web-reader-navigation-animation`, commit `d41365f5a9b8a3a5f1be3ff0a3ef49046c2dc047`.
Merge в `codex/mobile-ui-prototype`: `13b919e685a93308a3620a054315afd8566315fd`.
Проверенная ветка и merge имеют одинаковое дерево `services/web`:
`b2760734dea57a4a6bbc289f52d80f6e798fc61f`.

## Изменения и проверки

Нижняя мобильная навигация скрывается только внутри immersive-читалки. Кнопка выхода,
Escape и переход к настройкам восстанавливают вкладки и отступ под ними, сохраняя Мусхаф.
Перелистывание показывает уходящий и входящий листы с движением на полную ширину за 320 ms
и мягкой тенью края. Уходящий лист inert/aria-hidden; следующий свайп сразу меняет переход.
Выбор аята не запускает анимацию. Reduced motion учитывается. Предзагрузка, аудио,
сохранение позиции, сервер и нативный клиент этим релизом не изменялись.

52/52 браузерных сценария прошли: мобильная навигация и локали, аудио, жесты,
предзагрузка, сканы/QCF/Unicode в portrait и landscape, прерывание обратным свайпом,
доступность уходящего листа и reduced motion. Lint, TypeScript, production build,
CSS integrity (2 чанка, 117 315 байт) и diff check прошли.
Снимки середины перехода: `/private/tmp/iqro-mobile-review/reader-animation/full/`.

## Подготовка

Среда: `https://staging.iqro.forum`, `/opt/quran` на `162.55.35.8`.
Материалы: `/opt/quran/releases/web-reader-animation-20260909/`.

```text
source.tar.gz SHA256=a50f3cb244de67d49880c56907cd2602058c9a4aecae227f095a9cc0af36a675
BACKUP_FILE=/backups/quran_staging_20260909T072937Z.dump
backup SHA256=d0f3c96b63c27e9ddd21d3371816025d09db9f5326ca9c009b2359243dec49f4
```

Backup прошёл checksum и pg_restore --list. Сверенный скрипт запущен с
`BACKUP_RETENTION_DAYS=0`; старые копии сохранены, очистка не выполнялась.
Перед сборкой архив только `services/web` полностью передан и проверен по SHA256.
Изолированная сборка завершилась успешно. Ожидаемое ENOTFOUND backend при сборке
статического каталога дуа не препятствует runtime-проверке `/ru/dua` (HTTP 200).

## Rollout и откат

```text
WEB_IMAGE=quran-platform-web:staging-13b919e
Image ID=sha256:b1f199073711e20f03aa70a88d1cdaa2629d2813a3c7364dce3e10dae82d3526
revision=13b919e685a93308a3620a054315afd8566315fd
previous WEB_IMAGE=quran-platform-web:staging-08b4bdc
```

В 07:35 UTC обновлён только web через production/staging/budget overlays с
`--no-deps --no-build --detach --wait`. Web healthy, runtime budget verification прошёл.
ID и образы остальных восьми сервисов совпали со снимком до обновления.
Readiness: status=ok, database/cache/throttling=true.
HTTP 200: `/ru`, `/ru/quran`, `/ru/dua`, `/ru/audio`, `/ar/quran`.
После проверок обновлены веб-исходники и `.deployed-commit`.

Прежние web-образ, исходники и marker сохранены. Для отката выбрать
`WEB_IMAGE=quran-platform-web:staging-08b4bdc` тем же точечным Compose-вызовом.
Миграций нет. Журналы и снимки контейнеров находятся в каталоге релиза.

## Проверка в открытом браузере

- 390×844: выход из читалки вернул все пять нижних вкладок; результат проверен снимком.
- Повторное открытие скрывает навигацию. Переход 1 → 2 показал одновременно два
  настоящих листа с видимым краем и тенью; снимок получен во время анимации.
- 844×390: переход 2 → 3 также визуально проверен внутри анимации.
- Выполнены обратные переходы 3 → 2 → 1. Выход через настройки тоже возвращает вкладки.
- Возвращена страница 1 и восстановлен исходный viewport браузера.
- Localhost пересобран и оставлен на `http://127.0.0.1:3101` с прежним ограниченным API.

Настоящий Safari/iOS не входил в прогон.
