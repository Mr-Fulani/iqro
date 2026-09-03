BACKEND_DIR := services/backend
WEB_DIR := services/web
PRODUCTION_ENV ?= services/backend/.env.production
API_REPLICAS ?= 1
WEB_REPLICAS ?= 1
PRODUCTION_COMPOSE = DATABASE_API_REPLICAS=$(API_REPLICAS) PRODUCTION_ENV_FILE=$(PRODUCTION_ENV) docker compose --env-file $(PRODUCTION_ENV) -f compose.production.yaml
STAGING_ENV ?= ops/staging/staging.env
STAGING_REVISION ?= $(shell cut -c1-7 .deployed-commit 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || printf unknown)
STAGING_APP_VERSION ?= staging-$(STAGING_REVISION)
STAGING_COMPOSE = APP_VERSION=$(STAGING_APP_VERSION) PRODUCTION_ENV_FILE=$(abspath $(STAGING_ENV)) docker compose --env-file $(STAGING_ENV) -f compose.production.yaml -f compose.staging.yaml
STAGING_BUDGET_COMPOSE = COMPOSE_PARALLEL_LIMIT=1 $(STAGING_COMPOSE) -f compose.staging.budget.yaml
STAGING_RUNTIME_POSTGRES_IMAGE ?= $(shell container_id="$$( $(STAGING_COMPOSE) ps -q postgres 2>/dev/null )"; if [ -n "$$container_id" ]; then docker inspect --format '{{.Config.Image}}' "$$container_id" 2>/dev/null; fi)
STAGING_OPS_COMPOSE = POSTGRES_IMAGE=$(STAGING_RUNTIME_POSTGRES_IMAGE) $(STAGING_COMPOSE)

.PHONY: up down restart reset-all backend-install backend-check backend-test backend-migrations backend-run backend-up web-install web-dev web-build web-run mobile-check mobile-android-staging mobile-android-production mobile-ios-config-check mobile-ios-staging mobile-ios-production production-config production-build production-up production-scale-validate production-scale-preflight production-scale production-down production-ps production-logs production-backup production-backup-verify production-backup-offsite production-backup-offsite-verify production-backup-offsite-restore-check production-restore-check staging-init staging-preflight staging-email-configure staging-web-push-configure staging-media-configure staging-media-preflight staging-backup-offsite-configure staging-backup-offsite-preflight staging-config staging-build staging-up staging-down staging-ps staging-logs staging-runtime-postgres-image staging-backup staging-backup-verify staging-backup-offsite staging-backup-offsite-verify staging-backup-offsite-restore-check staging-restore-check staging-observability-config staging-observability-up staging-observability-down staging-budget-config staging-budget-build staging-budget-up staging-budget-runtime-verify staging-budget-scale-validate staging-budget-scale-preflight staging-budget-scale staging-budget-down staging-budget-ps staging-budget-logs observability-config observability-up observability-down observability-logs ops-backup ops-backup-verify ops-restore-check ops-load-smoke ops-audio-capacity ops-qf-audio-probe ops-sync-capacity ops-mixed-capacity ops-registered-capacity release-ops-check release-web-check release-check systemd-install

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

mobile-check:
	cd clients/iqro_mobile && flutter pub get --enforce-lockfile
	cd clients/iqro_mobile && dart format --output=none --set-exit-if-changed lib test
	cd clients/iqro_mobile && flutter gen-l10n
	git diff --exit-code -- clients/iqro_mobile/lib/l10n/generated
	cd clients/iqro_mobile && flutter analyze
	cd clients/iqro_mobile && flutter test

mobile-android-staging:
	cd clients/iqro_mobile && flutter build apk --debug --target-platform android-arm64 --dart-define=API_BASE_URL=https://staging.iqro.forum --dart-define=APP_ENV=staging --dart-define=APP_DOWNLOAD_URL=https://iqro.forum

mobile-android-production:
	cd clients/iqro_mobile && flutter build appbundle --release --dart-define=API_BASE_URL=https://iqro.forum --dart-define=APP_ENV=production --dart-define=APP_DOWNLOAD_URL=https://iqro.forum

mobile-ios-config-check:
	ruby -c clients/iqro_mobile/ios/Podfile
	plutil -lint clients/iqro_mobile/ios/Runner/Info.plist clients/iqro_mobile/ios/Flutter/AppFrameworkInfo.plist
	for file in clients/iqro_mobile/ios/Runner/*.lproj/InfoPlist.strings; do plutil -lint "$$file"; done
	cd clients/iqro_mobile/ios && pod install --deployment

mobile-ios-staging:
	cd clients/iqro_mobile && flutter build ios --debug --no-codesign --dart-define=API_BASE_URL=https://staging.iqro.forum --dart-define=APP_ENV=staging --dart-define=APP_DOWNLOAD_URL=https://iqro.forum

mobile-ios-production:
	cd clients/iqro_mobile && flutter build ios --release --no-codesign --dart-define=API_BASE_URL=https://iqro.forum --dart-define=APP_ENV=production --dart-define=APP_DOWNLOAD_URL=https://iqro.forum

production-config:
	$(PRODUCTION_COMPOSE) config --quiet

production-build:
	$(PRODUCTION_COMPOSE) build backend web gateway postgres

production-up:
	$(PRODUCTION_COMPOSE) up --build --detach --wait

production-scale-validate:
	python3 ops/scaling/validate.py \
		--api-replicas "$(API_REPLICAS)" \
		--web-replicas "$(WEB_REPLICAS)"

production-scale-preflight: production-scale-validate production-config
	$(PRODUCTION_COMPOSE) run --rm --no-deps backend \
		python manage.py database_connection_budget

production-scale: production-scale-preflight
	$(PRODUCTION_COMPOSE) up --detach --wait --no-build \
		--scale backend=$(API_REPLICAS) \
		--scale web=$(WEB_REPLICAS)

production-down:
	$(PRODUCTION_COMPOSE) down --remove-orphans

production-ps:
	$(PRODUCTION_COMPOSE) ps

production-logs:
	$(PRODUCTION_COMPOSE) logs --tail=200

production-backup:
	$(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-backup

production-backup-verify:
	$(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-backup-verify

production-backup-offsite: production-backup
	$(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-backup-offsite

production-backup-offsite-verify:
	$(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-backup-offsite-verify

production-backup-offsite-restore-check:
	$(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-backup-offsite-download
	BACKUP_FILE=/backups/offsite_restore.dump $(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-restore-check

production-restore-check:
	$(PRODUCTION_COMPOSE) --profile ops run --rm --no-deps db-restore-check

staging-init:
	python3 ops/staging/init.py \
		--output "$(STAGING_ENV)" \
		--host "$(STAGING_HOST)" \
		--media-host "$(STAGING_MEDIA_HOST)" \
		--acme-email "$(STAGING_ACME_EMAIL)" \
		--r2-account-id "$(STAGING_R2_ACCOUNT_ID)" \
		--r2-bucket "$(STAGING_R2_BUCKET)"

staging-preflight:
	python3 ops/staging/preflight.py --env-file "$(STAGING_ENV)"

staging-email-configure:
	python3 ops/staging/configure_email.py \
		--env-file "$(STAGING_ENV)" \
		--from-email "$(STAGING_EMAIL_FROM)"

staging-web-push-configure:
	python3 ops/staging/configure_web_push.py --env-file "$(STAGING_ENV)"

staging-media-configure:
	python3 ops/staging/configure_media.py \
		--env-file "$(STAGING_ENV)" \
		--account-id "$(STAGING_R2_ACCOUNT_ID)" \
		--bucket "$(STAGING_R2_BUCKET)"

staging-media-preflight:
	python3 ops/staging/preflight.py --env-file "$(STAGING_ENV)" --require-media

staging-backup-offsite-configure:
	python3 ops/staging/configure_backup.py \
		--env-file "$(STAGING_ENV)" \
		--account-id "$(STAGING_BACKUP_R2_ACCOUNT_ID)" \
		--bucket "$(STAGING_BACKUP_R2_BUCKET)"

staging-backup-offsite-preflight:
	python3 ops/staging/preflight.py --env-file "$(STAGING_ENV)" --require-offsite-backup

staging-config: staging-preflight
	$(STAGING_COMPOSE) config --quiet

staging-build: staging-config
	$(STAGING_COMPOSE) build backend web gateway postgres tls-proxy

staging-up: staging-config
	$(STAGING_COMPOSE) up --build --detach --wait

staging-down:
	$(STAGING_COMPOSE) down --remove-orphans

staging-ps:
	$(STAGING_COMPOSE) ps

staging-logs:
	$(STAGING_COMPOSE) logs --tail=200

staging-runtime-postgres-image:
	@test -n "$(STAGING_RUNTIME_POSTGRES_IMAGE)" || (printf '%s\n' 'ERROR: running staging PostgreSQL image was not found; restore the deployment first.' >&2; exit 1)

staging-backup: staging-runtime-postgres-image
	$(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-backup

staging-backup-verify: staging-runtime-postgres-image
	$(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-backup-verify

staging-backup-offsite: staging-runtime-postgres-image staging-backup-offsite-preflight staging-backup
	$(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-backup-offsite

staging-backup-offsite-verify: staging-runtime-postgres-image staging-backup-offsite-preflight
	$(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-backup-offsite-verify

staging-backup-offsite-restore-check: staging-runtime-postgres-image staging-backup-offsite-preflight
	$(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-backup-offsite-download
	BACKUP_FILE=/backups/offsite_restore.dump $(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-restore-check

staging-restore-check: staging-runtime-postgres-image
	$(STAGING_OPS_COMPOSE) --profile ops run --rm --no-deps db-restore-check

staging-observability-config: staging-preflight
	$(STAGING_COMPOSE) -f compose.observability.yaml config --quiet

staging-observability-up: staging-observability-config
	$(STAGING_COMPOSE) -f compose.observability.yaml up --detach --wait

staging-observability-down:
	$(STAGING_COMPOSE) -f compose.observability.yaml stop prometheus alertmanager grafana postgres-exporter redis-exporter celery-exporter
	$(STAGING_COMPOSE) -f compose.observability.yaml rm --force prometheus alertmanager grafana postgres-exporter redis-exporter celery-exporter observability-init

staging-budget-config: staging-preflight
	$(STAGING_BUDGET_COMPOSE) config --quiet

staging-budget-build: staging-budget-config
	$(STAGING_BUDGET_COMPOSE) build backend
	$(STAGING_BUDGET_COMPOSE) build web
	$(STAGING_BUDGET_COMPOSE) build gateway
	$(STAGING_BUDGET_COMPOSE) build postgres
	$(STAGING_BUDGET_COMPOSE) build tls-proxy

staging-budget-up: staging-budget-build
	$(STAGING_BUDGET_COMPOSE) up --no-build --detach --wait
	python3 ops/staging/verify_runtime_budget.py --env-file "$(STAGING_ENV)"

staging-budget-runtime-verify: staging-preflight
	python3 ops/staging/verify_runtime_budget.py --env-file "$(STAGING_ENV)"

staging-budget-scale-validate:
	python3 ops/scaling/validate.py \
		--api-replicas "$(API_REPLICAS)" \
		--web-replicas "$(WEB_REPLICAS)" \
		--max-api-replicas 2 \
		--max-web-replicas 2

staging-budget-scale-preflight: staging-budget-scale-validate staging-preflight
	DATABASE_API_REPLICAS=$(API_REPLICAS) $(STAGING_BUDGET_COMPOSE) config --quiet
	DATABASE_API_REPLICAS=$(API_REPLICAS) $(STAGING_BUDGET_COMPOSE) run --rm --no-deps backend \
		python manage.py database_connection_budget

staging-budget-scale: staging-budget-scale-preflight
	DATABASE_API_REPLICAS=$(API_REPLICAS) $(STAGING_BUDGET_COMPOSE) up --detach --wait --no-build \
		--scale backend=$(API_REPLICAS) \
		--scale web=$(WEB_REPLICAS)
	python3 ops/staging/verify_runtime_budget.py --env-file "$(STAGING_ENV)"

staging-budget-down:
	$(STAGING_BUDGET_COMPOSE) down --remove-orphans

staging-budget-ps:
	$(STAGING_BUDGET_COMPOSE) ps

staging-budget-logs:
	$(STAGING_BUDGET_COMPOSE) logs --tail=200

observability-config:
	$(PRODUCTION_COMPOSE) -f compose.observability.yaml config --quiet

observability-up:
	$(PRODUCTION_COMPOSE) -f compose.observability.yaml up --detach --wait

observability-down:
	$(PRODUCTION_COMPOSE) -f compose.observability.yaml stop prometheus alertmanager grafana postgres-exporter redis-exporter celery-exporter
	$(PRODUCTION_COMPOSE) -f compose.observability.yaml rm --force prometheus alertmanager grafana postgres-exporter redis-exporter celery-exporter observability-init

observability-logs:
	$(PRODUCTION_COMPOSE) -f compose.observability.yaml logs --tail=200 prometheus alertmanager grafana postgres-exporter redis-exporter celery-exporter

ops-backup:
	docker compose --profile ops run --rm db-backup

ops-backup-verify:
	docker compose --profile ops run --rm db-backup-verify

ops-restore-check:
	docker compose --profile ops run --rm db-restore-check

ops-load-smoke:
	python3 ops/load/smoke.py

ops-audio-capacity:
	python3 ops/load/audio_capacity.py $(AUDIO_CAPACITY_ARGS)

ops-qf-audio-probe:
	services/backend/.venv/bin/python ops/media/qf_audio_probe.py $(QF_AUDIO_PROBE_ARGS)

ops-sync-capacity:
	python3 ops/load/sync_capacity.py $(SYNC_CAPACITY_ARGS)

ops-mixed-capacity:
	python3 ops/load/mixed_capacity.py $(MIXED_CAPACITY_ARGS)

ops-registered-capacity:
	python3 ops/load/registered_capacity.py $(REGISTERED_CAPACITY_ARGS)

release-ops-check:
	sh -n ops/postgres/backup.sh
	sh -n ops/postgres/verify.sh
	sh -n ops/postgres/restore-check.sh
	sh -n ops/postgres/restore.sh
	sh -n ops/systemd/install.sh
	python3 -m ops.staging.test_config
	python3 -m unittest \
		ops.postgres.test_offsite \
		ops.monitoring.test_heartbeat \
		ops.systemd.test_units \
		ops.load.test_smoke \
		ops.load.test_capacity \
		ops.load.test_audio_capacity \
		ops.load.test_sync_capacity \
		ops.gateway.test_config \
		ops.media.test_contract \
		ops.observability.test_render_config \
		ops.scaling.test_validate
	APP_VERSION=release-check PRODUCTION_ENV_FILE=./services/backend/.env.production.example \
		docker compose --env-file services/backend/.env.production.example \
		-f compose.production.yaml config --quiet

release-web-check:
	cd $(WEB_DIR) && npm run lint
	cd $(WEB_DIR) && npm run typecheck
	cd $(WEB_DIR) && npm run test:cache
	cd $(WEB_DIR) && npm run test:public-contracts
	cd $(WEB_DIR) && npm run build
	cd $(WEB_DIR) && npm run test:e2e
	cd $(WEB_DIR) && npm run test:e2e:production
	cd $(WEB_DIR) && npm run test:lighthouse

release-check: release-ops-check backend-check backend-test release-web-check

systemd-install:
	sudo sh ops/systemd/install.sh "$(CURDIR)/ops/systemd"
