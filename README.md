# Quran Platform

Многоклиентская исламская контентная платформа с единым API для Flutter iOS/Android,
веб-сайта и Telegram Mini App. Текущий вертикальный срез охватывает Коран, аудио, время
намаза, напоминания, заучивание и версионированный каталог ду’а; архитектура предусматривает
отдельные домены переводов, тафсиров, хадисов, книг и образовательных подборок.

Утверждённая спецификация: [техническое задание](thoughts/shared/specs/2026-08-09-quran-platform-backend.md).

## Структура

- `services/backend` — Django API и фоновые задачи;
- `services/web` — Next.js-клиент для Корана, Мусхафа, аудио и личного кабинета;
- `ops` — проверяемые сценарии мониторинга, резервного копирования, load/capacity и managed
  media CDN contracts;
- `thoughts/shared/specs` — утверждённые продуктовые и технические спецификации;
- мобильный Flutter-клиент будет добавлен отдельным workspace-пакетом;
- Telegram Mini App будет использовать общий API и типизированные web/domain пакеты, но
  отдельные Telegram auth/deployment adapters.

Текущий срез содержит публичный каталог Корана, 604 интерактивные страницы Мусхафа,
каталог чтецов, version-pinned аудиотреки и таймкоды аятов, автоматическое обновление
Quran.Foundation, безопасную гостевую авторизацию, позицию чтения, закладки, offline-sync,
время намаза, заучивание, полный локализованный каталог «Хисн аль-Муслим» из 267 карточек
и 132 тем, а также операторский workflow.
На web доступны воспроизведение целой суры и поаятное воспроизведение непосредственно в
Мусхафе.

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

Production-наблюдаемость, резервные копии PostgreSQL, restore drill, безопасный нагрузочный
smoke и staged read-only capacity harness описаны в
[операционном runbook](docs/operations.md).
Production Compose без hot reload и bind-mount исходников описан в
[руководстве по production-запуску](docs/production.md).
Создание первой публичной тестовой среды от пустого VPS до DNS/TLS/R2 описано в
[пошаговом staging runbook](docs/staging.md).
Актуальное соответствие утверждённому P0/MVP и приоритетный backlog зафиксированы в
[P0/MVP gap audit](docs/mvp-gap-audit.md).
Правила расширения функций и мощности до 100 000 DAU описаны в
[архитектуре расширения и масштабирования](docs/architecture-and-scaling.md), а порядок
реализации — в [плане и roadmap](docs/roadmap.md).
Технические доказательства, внешние sign-off и rollback для Quran dataset фиксируются в
[Quran content acceptance record](docs/quran-content-acceptance.md).

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
