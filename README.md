# Quran Platform

Многоклиентская платформа для чтения и прослушивания Корана, расчёта времени намаза и персональных напоминаний.

Утверждённая спецификация: [техническое задание](thoughts/shared/specs/2026-08-09-quran-platform-backend.md).

## Структура

- `services/backend` — Django API и фоновые задачи;
- `thoughts/shared/specs` — утверждённые продуктовые и технические спецификации;
- клиентские приложения Flutter и Next.js будут добавляться отдельными workspace-пакетами.

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
