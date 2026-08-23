# Production-запуск

`compose.production.yaml` запускает отдельный production-стек: PostgreSQL, Redis,
одноразовую миграцию, Django/Gunicorn, Celery worker/beat, Next.js standalone и Nginx
gateway. Исходный код не монтируется в контейнеры, наружу публикуется только gateway,
а миграция должна успешно завершиться до запуска приложения.

Домен/TLS, внешний мониторинг и offsite-хранилище резервных копий пока намеренно не
включены. До публичного запуска они остаются обязательными инфраструктурными задачами.

## 1. Окружение и секреты

Создайте production-файл из шаблона:

```bash
cp services/backend/.env.production.example services/backend/.env.production
chmod 600 services/backend/.env.production
```

Замените все значения `replace-me`. Для каждого ключа используйте отдельное случайное
значение; секреты development-среды переиспользовать нельзя. Проверьте как минимум:

- `DJANGO_ALLOWED_HOSTS`, CSRF/CORS origins и публичные HTTPS URL;
- пароль PostgreSQL и все Django/Quran hash keys;
- `QURAN_OPERATIONS_TOKEN`;
- Quran.Foundation credentials, если синхронизация включена;
- `QURAN_MEDIA_DIR`: каталог с импортированным dataset и 604 страницами Мусхафа.

Файл `.env.production` игнорируется Git. В контейнеры он передаётся через `env_file`,
но не копируется в образы.

## 2. Проверка и запуск

Остановите development-стек либо назначьте production другой `GATEWAY_PORT`, затем:

```bash
make production-config
make production-build
make production-up
make production-ps
```

По умолчанию gateway слушает только `127.0.0.1:3000`. Это безопасная настройка для
reverse proxy на том же сервере. Для публичного запуска TLS-proxy должен передавать
`Host`, `X-Forwarded-For` и `X-Forwarded-Proto: https`. Не выставляйте gateway на
`0.0.0.0` без firewall и настроенного TLS.

Проверки после запуска:

```bash
curl --fail http://127.0.0.1:3000/healthz
curl --fail --header 'X-Forwarded-Proto: https' \
  http://127.0.0.1:3000/api/v1/health/ready
python3 ops/load/smoke.py --base-url http://127.0.0.1:3000
```

Для временной проверки только на loopback без TLS можно установить
`DJANGO_SECURE_SSL_REDIRECT=false`. В реальном окружении значение должно оставаться
`true`.

## 3. Что обеспечивает Compose

- backend и web собираются в production targets и работают без hot reload;
- контейнеры приложения имеют read-only root filesystem, `no-new-privileges`,
  ограничение процессов, CPU и RAM;
- healthchecks проверяют PostgreSQL, Redis, Django readiness, Next.js и gateway;
- логи Docker ротируются по размеру и количеству файлов;
- только успешная `migrate --noinput` открывает запуск backend/worker/beat;
- Nginx раздаёт `/media/` и собранный Django `/static/`, а `/api/` проксирует в backend;
- данные PostgreSQL/Redis и собранная статика находятся в именованных volumes.

Лимиты ресурсов задаются в `compose.production.yaml`. Перед размещением на маленьком
сервере сравните их сумму с доступной RAM; Docker применяет лимит каждому сервису
отдельно.

## 4. Обновление и откат

Перед обновлением создайте и проверьте backup:

```bash
make production-backup
export BACKUP_FILE=/backups/quran_YYYYMMDDTHHMMSSZ.dump
make production-backup-verify
make production-restore-check
```

Эти команды проверяют локальную копию. Пока offsite bucket отложен, backup всё ещё
нужно вручную переносить на отдельный зашифрованный носитель; backup на том же диске
не защищает от отказа диска или потери сервера.

Затем обновите checkout/образы и повторите `make production-up`. Чтобы откат был
воспроизводимым, в production задавайте неизменяемые `BACKEND_IMAGE`, `WEB_IMAGE` и
`GATEWAY_IMAGE` (version tag или digest), а предыдущие значения сохраняйте в журнале
релиза. Миграции должны быть обратно совместимыми с предыдущей версией приложения.

Остановка без удаления данных:

```bash
make production-down
```

Эта команда сохраняет все volumes. Удаление volumes не входит в штатный runbook.

## 5. Диагностика

```bash
make production-ps
make production-logs
docker compose --env-file services/backend/.env.production \
  -f compose.production.yaml logs --tail=200 backend gateway
```

Если `migrate` завершилась с ошибкой, зависимые сервисы не запустятся. Исправьте причину,
повторно запустите одноразовую миграцию и затем весь стек. Не обходите migration gate.

Операционные health/metrics endpoints, backup/restore и load-smoke подробно описаны в
[operations.md](operations.md).
