# Quran Platform

Многоклиентская платформа для чтения и прослушивания Корана, расчёта времени намаза и персональных напоминаний.

Утверждённая спецификация: [техническое задание](thoughts/shared/specs/2026-08-09-quran-platform-backend.md).

## Структура

- `services/backend` — Django API и фоновые задачи;
- `thoughts/shared/specs` — утверждённые продуктовые и технические спецификации;
- клиентские приложения Flutter и Next.js будут добавляться отдельными workspace-пакетами.

Текущий backend-срез уже содержит публичный каталог Корана, безопасную гостевую
авторизацию и устройства, refresh rotation/replay detection, позицию чтения, закладки,
offline-sync, bounded retention, MVP обратной связи с операторским workflow и проверяемый
конвейер PDF → WebP для 604 страниц Мусхафа. Следующий приоритетный срез добавляет каталог
чтецов, version-pinned аудиотреки, таймкоды аятов и CDN/offline contract.

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
