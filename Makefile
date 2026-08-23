BACKEND_DIR := services/backend
WEB_DIR := services/web

.PHONY: up down restart reset-all backend-install backend-check backend-test backend-migrations backend-run backend-up web-install web-dev web-build web-run ops-backup ops-backup-verify ops-restore-check ops-load-smoke

# Запуск с сохранением данных базы данных
up:
	docker compose up --build

# Остановка с сохранением данных базы данных
down:
	docker compose down --remove-orphans

# Перезапуск с сохранением данных базы данных
restart:
	docker compose down --remove-orphans && docker compose up --build

# Полный сброс (с удалением томов базы данных и Redis)
reset-all:
	docker compose down -v --remove-orphans && docker compose up --build

backend-install:
	cd $(BACKEND_DIR) && uv sync --all-groups

backend-check:
	cd $(BACKEND_DIR) && uv run ruff check .
	cd $(BACKEND_DIR) && uv run ruff format --check .
	cd $(BACKEND_DIR) && uv run mypy src
	cd $(BACKEND_DIR) && uv run python manage.py check
	cd $(BACKEND_DIR) && uv run python manage.py makemigrations --check --dry-run

backend-test:
	cd $(BACKEND_DIR) && uv run pytest

backend-migrations:
	cd $(BACKEND_DIR) && uv run python manage.py makemigrations
	cd $(BACKEND_DIR) && uv run python manage.py migrate

backend-run:
	cd $(BACKEND_DIR) && uv run python manage.py runserver

backend-up:
	docker compose -f $(BACKEND_DIR)/compose.yaml up --build

web-install:
	cd $(WEB_DIR) && npm install

web-dev:
	cd $(WEB_DIR) && npm run dev

web-build:
	cd $(WEB_DIR) && npm run build

web-run:
	cd $(WEB_DIR) && npm start

ops-backup:
	docker compose --profile ops run --rm db-backup

ops-backup-verify:
	docker compose --profile ops run --rm db-backup-verify

ops-restore-check:
	docker compose --profile ops run --rm db-restore-check

ops-load-smoke:
	python3 ops/load/smoke.py
