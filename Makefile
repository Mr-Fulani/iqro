BACKEND_DIR := services/backend

.PHONY: backend-install backend-check backend-test backend-migrations backend-run backend-up

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
