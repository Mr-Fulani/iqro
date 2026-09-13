# Quran Platform

Многоклиентская исламская контентная платформа с единым API для Flutter iOS/Android,
веб-сайта и Telegram Mini App. Текущий вертикальный срез охватывает Коран, аудио, время
намаза, напоминания, заучивание и версионированный каталог ду’а; архитектура предусматривает
отдельные домены переводов, тафсиров, хадисов, книг и образовательных подборок.

Утверждённая спецификация: [техническое задание](thoughts/shared/specs/2026-08-09-quran-platform-backend.md).

## Структура

- `services/backend` — Django API и фоновые задачи;
- `services/web` — Next.js-клиент для Корана, Мусхафа, аудио и личного кабинета;
- `clients/iqro_mobile` — нативный Flutter-клиент Android с local-first хранением;
- `ops` — проверяемые сценарии мониторинга, резервного копирования, load/capacity и managed
  media CDN contracts;
- `thoughts/shared/specs` — утверждённые продуктовые и технические спецификации;
- Telegram Mini App будет использовать общий API и типизированные web/domain пакеты, но
  отдельные Telegram auth/deployment adapters.

Текущий срез содержит публичный каталог Корана, 604 интерактивные страницы Мусхафа,
каталог чтецов, version-pinned аудиотреки и таймкоды аятов, автоматическое обновление
Quran.Foundation, безопасную гостевую авторизацию, позицию чтения, закладки, offline-sync,
время намаза, заучивание, полный локализованный каталог «Хисн аль-Муслим» из 267 карточек
и 132 тем, а также операторский workflow.
На web доступны воспроизведение целой суры и поаятное воспроизведение непосредственно в
Мусхафе.

## Первый запуск разработчика

Каждый разработчик запускает собственные backend, PostgreSQL и Redis. Общего тестового
сервера нет. Миграции создают структуру БД и встроенные каталоги ду’а/намаза;
Коран, страницы, переводы, тафсиры и аудио автоматически подготавливает команда запуска.

Нужны Git, Python 3 для управляющего скрипта и запущенный Docker с Compose v2.
Python 3.14, Node.js и инструменты формирования страниц устанавливаются внутри образов.
Для мобильного клиента дополнительно нужны Flutter и Android SDK либо Xcode.

```bash
git clone <URL-репозитория>
cd quran
make dev-init
# Заполните QF_CLIENT_ID, QF_CLIENT_SECRET и QF_ENV в services/backend/.env
make up
```

Открыть сайт: http://localhost:3000. API: http://localhost:8000/api/v1,
Swagger: http://localhost:8000/api/docs. Изменения исходников подхватываются автоматически.

`make up` автоматически загружает каталог ду’а из репозитория, Мусхаф из Quran.Foundation,
проверяет закреплённый корпус Корана и создаёт 604 страницы KFGQPC для мобильного клиента.
Все переводы и тафсиры, перечисленные в `.env`, а также потоковое аудио одного чтеца
со всеми 114 сурами и таймкодами загружаются автоматически.
Повторный запуск проверяет БД/медиа и загружает только недостающее; готовые данные
работают без обращения к источнику. После ошибки достаточно повторить `make up`.
Ключи API остаются только в backend; файла `.env` самого по себе недостаточно.

```bash
# Мобильное приложение (сначала автоматически подготовит backend и данные):
make mobile-run
# Android Emulator: API выбирается автоматически как http://10.0.2.2:8000
# iOS Simulator: http://127.0.0.1:8000

# Если работаете только над web и хотите пропустить создание мобильных страниц:
make up DEV_UP_ARGS=--web-only
```

Подробности, установка инструментов, физический телефон, аудио и устранение ошибок:
[локальная разработка](docs/local-development.md).
Работа с ветками, миграциями и проверками: [CONTRIBUTING.md](CONTRIBUTING.md).
Архитектура мобильного клиента: [mobile README](clients/iqro_mobile/README.md).

Production-наблюдаемость, резервные копии PostgreSQL, restore drill, безопасный нагрузочный
smoke и staged read-only capacity harness описаны в
[операционном runbook](docs/operations.md).
Production Compose без hot reload и bind-mount исходников описан в
[руководстве по production-запуску](docs/production.md).
Текущее состояние offsite backup, внешнего heartbeat, GitHub CI и оставшиеся внешние gates
зафиксированы в [release hardening record](docs/release/release-hardening-2026-08-29.md).
Архивный регламент создания отдельной тестовой среды от VPS до DNS/TLS/R2 описан в
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
make dev-up
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
