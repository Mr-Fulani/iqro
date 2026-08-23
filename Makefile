BACKEND_DIR := services/backend
WEB_DIR := services/web
PRODUCTION_ENV ?= services/backend/.env.production
PRODUCTION_COMPOSE = PRODUCTION_ENV_FILE=$(PRODUCTION_ENV) docker compose --env-file $(PRODUCTION_ENV) -f compose.production.yaml

.PHONY: up down restart reset-all backend-install backend-check backend-test backend-migrations backend-run backend-up web-install web-dev web-build web-run production-config production-build production-up production-down production-ps production-logs production-backup production-backup-verify production-restore-check ops-backup ops-backup-verify ops-restore-check ops-load-smoke

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

production-config:
	$(PRODUCTION_COMPOSE) config --quiet

production-build:
	$(PRODUCTION_COMPOSE) build backend web gateway

production-up:
	$(PRODUCTION_COMPOSE) up --build --detach --wait

production-down:
	$(PRODUCTION_COMPOSE) down --remove-orphans

production-ps:
	$(PRODUCTION_COMPOSE) ps

production-logs:
	$(PRODUCTION_COMPOSE) logs --tail=200

production-backup:
	$(PRODUCTION_COMPOSE) --profile ops run --rm db-backup

production-backup-verify:
	$(PRODUCTION_COMPOSE) --profile ops run --rm db-backup-verify

production-restore-check:
	$(PRODUCTION_COMPOSE) --profile ops run --rm db-restore-check

ops-backup:
	docker compose --profile ops run --rm db-backup

ops-backup-verify:
	docker compose --profile ops run --rm db-backup-verify

ops-restore-check:
	docker compose --profile ops run --rm db-restore-check

ops-load-smoke:
	python3 ops/load/smoke.py
