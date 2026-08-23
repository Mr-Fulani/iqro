# Quran Platform

Многоклиентская платформа для чтения и прослушивания Корана, расчёта времени намаза и персональных напоминаний.

Утверждённая спецификация: [техническое задание](thoughts/shared/specs/2026-08-09-quran-platform-backend.md).

## Структура

- `services/backend` — Django API и фоновые задачи;
- `services/web` — Next.js-клиент для Корана, Мусхафа, аудио и личного кабинета;
- `thoughts/shared/specs` — утверждённые продуктовые и технические спецификации;
- мобильный Flutter-клиент будет добавлен отдельным workspace-пакетом.

Текущий срез содержит публичный каталог Корана, 604 интерактивные страницы Мусхафа,
каталог чтецов, version-pinned аудиотреки и таймкоды аятов, автоматическое обновление
Quran.Foundation, безопасную гостевую авторизацию, позицию чтения, закладки, offline-sync,
время намаза и операторский workflow. На web доступны воспроизведение целой суры и
поаятное воспроизведение непосредственно в Мусхафе.

## Быстрый старт backend

Требуются Docker Compose либо Python 3.14, PostgreSQL и Redis.

```bash
cp services/backend/.env.example services/backend/.env
docker compose -f services/backend/compose.yaml up --build
```

После запуска:

- liveness: `http://localhost:8000/api/v1/health/live`;
- readiness: `http://localhost:8000/api/v1/health/ready`;
- OpenAPI: `http://localhost:8000/api/schema`;
- Swagger UI: `http://localhost:8000/api/docs`.

## Полный локальный стек

```bash
docker compose up --build
```

Web доступен на `http://localhost:3000`. Корневой Compose использует development-target
с hot reload. Production-образ собирается последним target из `services/web/Dockerfile`:

```bash
docker build \
  --build-arg BACKEND_INTERNAL_URL=http://backend:8000 \
  -t quran-web:production \
  services/web
```

Образ запускает минимальный Next.js standalone server от непривилегированного пользователя
и содержит встроенный healthcheck. Адрес backend для rewrites фиксируется при сборке через
`BACKEND_INTERNAL_URL`.

## Проверки web

```bash
cd services/web
npm ci
npx playwright install chromium
npm run lint
npm run typecheck
npm run build
npm run test:e2e
```
