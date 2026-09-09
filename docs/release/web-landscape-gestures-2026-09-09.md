# Исправление сенсорных свайпов Мусхафа, 9 сентября 2026

## Развёрнутая версия

9 сентября 2026, 08:44 UTC: frontend версии `8064be5` развёрнут на
`https://staging.iqro.forum`. Обновлён только web; идентификаторы остальных восьми
контейнеров не изменились. Полные тестовые наборы при завершении деплоя не повторялись.

Ветка `codex/web-landscape-gestures`:
- `c1d2ba0e174920c7dc904d8d315c2c1b4f1fd5fe` — обработка сенсорных жестов и тесты;
- `23051b6` — совместимые параметры мобильного тестового контекста.

Merge в `codex/mobile-ui-prototype`: `8064be5ca96a96579bc8288e12797eccb8181ac2`.
Дерево `services/web`: `9a627831aa61518481f0f04b28364fbb8b28b8f3`.

Изменены только веб-компонент жестов, подключение к странице Мусхафа, стили наведения/
выделения и проверки. Touch-поток больше не зависит от завершения pointer-потока;
свайп и отменённое/короткое движение подавляют последующий выбор аята. Вертикальная
прокрутка и одиночный tap сохранены. Подробности и ограничения проверки находятся
в `services/web/docs/mobile-presentation-review.md`.

22 целевых сценария прошли до последней корректировки отмены при повороте. Затем 8/8
проверок прошли на финальной сборке, включая мобильный профиль Pixel 7 landscape;
4/4 расширенных сценария проверили быстрый обратный свайп с одной позиции экрана
во время анимации. Два сценария WebKit прошли после настройки локального HTTPS и
переносимого тестового touch-события; это не физический iPhone. После удаления
неподдерживаемого поля screen прошли TypeScript и оба сенсорных сценария Android.
Lint, сборка приложения, CSS integrity (2 чанка, 117 660 байт) и diff check прошли.
ADB не обнаружил физических устройств. Точный пользовательский симптом на физическом
Android не подтверждён локально; эмуляция не выдаётся за проверку на устройстве.

## Frontend-only rollout

```text
archive=/private/tmp/iqro-landscape-gestures/source-8064be5.tar.gz
SHA256=3db377ad7d0304d72fe56ea76500b7488224bd78d6cea3951f34d3d76a55de31
destination=root@162.55.35.8:/opt/quran/releases/web-landscape-gestures-20260909/source-8064be5.tar.gz
WEB_IMAGE=quran-platform-web:staging-8064be5
image digest=sha256:929538515a214a5bd7c6123fd815d617479c3db8a12c9880603122f3b9e56207
web container=0446a1fef45ce5405ded77f032ec8043acdca347884d16dc629ccbfdbc4e2310
.deployed-commit=8064be5ca96a96579bc8288e12797eccb8181ac2
rollback WEB_IMAGE=quran-platform-web:staging-13b919e
rollback revision=13b919e685a93308a3620a054315afd8566315fd
```

Архив содержит только отслеживаемый Git каталог `services/web`; .env, ключей и
credentials в составе нет. Пользователь явно разрешил передачу исправленного архива
на этот staging-сервер. SHA256 на сервере совпал. Сборка runner-образа, TypeScript и
встроенная проверка CSS integrity завершились успешно. Изолированная сборка вывела
ожидаемые предупреждения ENOTFOUND backend для SSR каталога дуа.

Переключение выполнено через существующий compose-путь `up --no-deps --no-build web`.
Web получил статус healthy, проверка runtime budget прошла. Readiness API вернул
`status=ok`, database/cache/throttling=true; `/ru/quran` и `/ar/quran` ответили HTTP 200.
Исходники `services/web` и маркер развёрнутого коммита приведены к версии образа.

Для этого frontend-only изменения новый дамп не создавался. Сохранённый backup
`/backups/quran_staging_20260909T072937Z.dump` (SHA256
`d0f3c96b63c27e9ddd21d3371816025d09db9f5326ca9c009b2359243dec49f4`) повторно прошёл checksum
и pg_restore --list. Снимок контейнеров и verification log сохранены в каталоге релиза.
Все старые резервные копии и образы сохранены, операции очистки не выполнялись.

## Короткая проверка после деплоя и откат

Smoke на настоящих страницах staging без моков прошёл в Chrome с мобильным профилем
Pixel 7 landscape: сенсорные свайпы 3 → 4 → 3, быстрый обратный жест во время анимации,
отсутствие случайного выделения, вертикальная прокрутка и выделение отдельным tap.
Ошибок JavaScript страницы не было. Это эмуляция сенсорного ввода, а не физический Android.
Снимок: `/private/tmp/iqro-landscape-gestures/staging-android-after.png`.

Старый образ сохранён. В каталоге релиза сохранены `previous-web-source.tar`,
`previous-web-image.txt`, `previous-deployed-commit`, снимки контейнеров, логи сборки,
rollout, runtime budget и readiness. Откат выполняется тем же web-only compose-путём
с предыдущим образом и восстановлением сохранённых исходников/маркера.
