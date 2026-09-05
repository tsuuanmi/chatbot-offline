SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

VERSIONS_ENV ?= versions.env
RUNTIME_ENV ?= .env
APP_TAG ?= chatbot-offline/app:local
AUTH_REGISTRY ?= runtime/secrets/chat_auth.json
CLIENT_API_KEY ?= runtime/secrets/chat_api_key
GATEWAY_PORT ?= 18080
GATEWAY_URL ?= http://127.0.0.1:$(GATEWAY_PORT)

COMPOSE = env \
	-u CHATBOT_IMAGE \
	-u HAYHOOKS_IMAGE \
	-u LLAMA_CPU_IMAGE \
	-u POSTGRES_IMAGE \
	-u NGINX_IMAGE \
	-u EMBEDDING_MODEL \
	-u EMBEDDING_DIMENSION \
	docker compose \
	--env-file $(RUNTIME_ENV) \
	--env-file $(VERSIONS_ENV)

TOOLS = $(COMPOSE) --profile tools


.PHONY: \
	help \
	check-env \
	config \
	build \
	up \
	up-recreate \
	down \
	restart \
	offline-restart \
	ps \
	status \
	health \
	logs \
	migrate \
	index \
	reindex \
	llama-health \
	test-policy \
	smoke-m5c \
	check-python \
	verify \
	clean


help:
	@printf '%s\n' \
		'chatbot-offline development commands' \
		'' \
		'  make build              Build app image and pin CHATBOT_IMAGE' \
		'  make up                 Start stack, wait until healthy' \
		'  make up-recreate        Recreate stack and wait until healthy' \
		'  make down               Stop stack without deleting data' \
		'  make restart            down + up' \
		'  make offline-restart    Restart using local images only' \
		'  make ps                 Show services' \
		'  make status             Show Hayhooks status' \
		'  make health             ps + Hayhooks status' \
		'  make logs               Tail all logs' \
		'  make logs SERVICE=x     Tail one service, e.g. chatbot' \
		'  make migrate            Run database migrations' \
		'  make index              Run knowledge indexer' \
		'  make reindex            Safely rebuild knowledge index' \
		'  make llama-health       Check llama.cpp health' \
		'  make test-policy        Run both domain/risk calibration suites' \
		'  make smoke-m5c          Run deterministic M5C smoke tests' \
		'  make check-python       Compile Python source inside container' \
		'  make verify             Run common acceptance checks' \
		'  make config             Validate rendered Compose config'


check-env:
	@test -f "$(VERSIONS_ENV)" || { \
		echo "Missing $(VERSIONS_ENV)" >&2; \
		exit 1; \
	}
	@test -f "$(RUNTIME_ENV)" || { \
		echo "Missing $(RUNTIME_ENV)" >&2; \
		exit 1; \
	}


config: check-env
	@$(COMPOSE) config >/dev/null
	@echo "COMPOSE CONFIG OK"


build: check-env
	@set -a; \
	source "$(VERSIONS_ENV)"; \
	set +a; \
	: "$${HAYHOOKS_IMAGE:?HAYHOOKS_IMAGE is required}"; \
	: "$${EMBEDDING_MODEL:?EMBEDDING_MODEL is required}"; \
	: "$${EMBEDDING_DIMENSION:?EMBEDDING_DIMENSION is required}"; \
	docker build \
		--build-arg HAYHOOKS_IMAGE="$$HAYHOOKS_IMAGE" \
		--build-arg EMBEDDING_MODEL="$$EMBEDDING_MODEL" \
		--build-arg EMBEDDING_DIMENSION="$$EMBEDDING_DIMENSION" \
		-t "$(APP_TAG)" \
		.; \
	image_id="$$(docker image inspect "$(APP_TAG)" --format '{{.Id}}')"; \
	sed -i '/^CHATBOT_IMAGE=/d' "$(VERSIONS_ENV)"; \
	printf 'CHATBOT_IMAGE=%s\n' "$$image_id" >> "$(VERSIONS_ENV)"; \
	echo "CHATBOT_IMAGE=$$image_id"


up: check-env check-auth
	@$(COMPOSE) up -d --pull never --wait


up-recreate: check-env check-auth
	@$(COMPOSE) up \
		-d \
		--pull never \
		--force-recreate \
		--wait


down: check-env
	@$(COMPOSE) down


restart: down up


offline-restart: check-env check-auth
	@$(COMPOSE) down
	@$(COMPOSE) up -d --pull never --wait
	@echo "OFFLINE RESTART OK"


ps: check-env
	@$(COMPOSE) ps


status:
	@curl -fsS http://127.0.0.1:1416/status
	@echo


health: ps status ready gateway-status gateway-ready


logs: check-env
	@$(COMPOSE) logs \
		--tail=200 \
		-f \
		$(if $(SERVICE),$(SERVICE),)


migrate: check-env
	@$(TOOLS) run --rm db-migrate


index: check-env
	@$(TOOLS) run --rm index-knowledge


reindex: check-env
	@echo "Stopping chatbot before recreating knowledge table..."
	@$(COMPOSE) stop chatbot
	@$(COMPOSE) up -d postgres --wait
	@$(TOOLS) run --rm index-knowledge
	@$(COMPOSE) up -d chatbot --pull never --wait
	@echo "REINDEX OK"


llama-health: check-env
	@$(COMPOSE) exec -T llama-server \
		curl -fsS http://127.0.0.1:8080/health
	@echo


test-policy: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" python3 -m tests.integration.test_domain_policy_api \
		tests/data/domain_calibration.json
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" python3 -m tests.integration.test_domain_policy_api \
		tests/data/domain_boundary_calibration.json


smoke-m5c: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" python3 tools/smoke_m5c.py


check-python: check-env
	@$(COMPOSE) exec -T chatbot \
		python -c "from pathlib import Path; roots=[Path('/app/chatbot_app'),Path('/app/pipelines')]; files=sorted(p for root in roots for p in root.rglob('*.py')); [compile(p.read_text(encoding='utf-8'),str(p),'exec') for p in files]; print(f'PYTHON COMPILE OK ({len(files)} files)')"


verify: config health test-unit check-tests test-policy smoke-m5c smoke-api-contract smoke-stream smoke-gateway check-python
	@echo
	@echo "VERIFY PASS"


clean:
	@rm -f /tmp/chatbot-offline-*.json

.PHONY: stop-llama start-llama

stop-llama: check-env
	@$(COMPOSE) stop llama-server

start-llama: check-env
	@$(COMPOSE) up -d llama-server --pull never --wait


.PHONY: smoke-history db-history

smoke-history: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" python3 tools/smoke_history.py


db-history: check-env
	@$(COMPOSE) exec -T postgres sh -lc \
		'psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -x -c "SELECT c.id AS conversation_id, c.owner_id, t.turn, t.domain, t.risk, t.source, left(t.query, 80) AS query, t.created_at FROM conversation_turns AS t JOIN conversations AS c ON c.id = t.conversation_id ORDER BY t.created_at DESC LIMIT 20;"'


.PHONY: logs-tail

logs-tail: check-env
	@$(COMPOSE) logs \
		--tail=$${LINES:-150} \
		$(if $(SERVICE),$(SERVICE),)


.PHONY: env-info

env-info:
	@echo "=== shell overrides ==="
	@env | grep -E \
		'^(CHATBOT_IMAGE|HAYHOOKS_IMAGE|LLAMA_CPU_IMAGE|POSTGRES_IMAGE|NGINX_IMAGE|EMBEDDING_MODEL|EMBEDDING_DIMENSION)=' \
		|| echo "(none)"
	@echo
	@echo "=== versions.env ==="
	@grep -E \
		'^(CHATBOT_IMAGE|HAYHOOKS_IMAGE|LLAMA_CPU_IMAGE|POSTGRES_IMAGE|NGINX_IMAGE|EMBEDDING_MODEL|EMBEDDING_DIMENSION)=' \
		"$(VERSIONS_ENV)"


.PHONY: rebuild image-info

rebuild: build up-recreate
	@echo "REBUILD OK"


image-info: check-env
	@echo "=== versions.env ==="
	@grep '^CHATBOT_IMAGE=' "$(VERSIONS_ENV)"
	@echo
	@echo "=== compose resolved ==="
	@$(COMPOSE) config \
		| sed -n '/^  chatbot:/,/^  [a-zA-Z]/p' \
		| grep 'image:'
	@echo
	@echo "=== running container ==="
	@docker inspect chatbot-offline-chatbot-1 \
		--format 'configured={{.Config.Image}} actual={{.Image}}'

.PHONY: test test-unit test-integration

test: test-unit


test-unit:
	@python3 -m unittest \
		discover \
		-s tests/unit \
		-t . \
		-p 'test_*.py' \
		-v


test-integration:
	@python3 -m unittest \
		discover \
		-s tests/integration \
		-t . \
		-p 'test_*.py' \
		-v

.PHONY: check-tests

check-tests:
	@python3 -c "from pathlib import Path; files=sorted(Path('tests').rglob('*.py')); [compile(p.read_text(encoding='utf-8'),str(p),'exec') for p in files]; print(f'TEST PYTHON COMPILE OK ({len(files)} files)')"


.PHONY: ready

ready:
	@curl -fsS \
		-X POST \
		http://127.0.0.1:1416/healthcheck/run \
		-H 'Content-Type: application/json' \
		-d '{}'
	@echo


.PHONY: smoke-api-contract

smoke-api-contract: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" python3 tools/smoke_api_contract.py


.PHONY: smoke-history-context

smoke-history-context: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" python3 tools/smoke_history_context.py


.PHONY: smoke-history-concurrency

smoke-history-concurrency: check-env
	@$(COMPOSE) exec -T chatbot \
		python /app/tools/smoke_history_concurrency.py


.PHONY: auth-bootstrap check-auth smoke-auth

auth-bootstrap:
	@CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 -m tools.bootstrap_auth


check-auth:
	@CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 -m tools.bootstrap_auth --check


smoke-auth: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 tools/smoke_auth.py


.PHONY: smoke-ownership

smoke-ownership: check-auth
	@python3 tools/smoke_ownership.py


.PHONY: auth-rotate

auth-rotate: check-env
	@test -n "$(OWNER)" || { echo "OWNER is required" >&2; exit 1; }
	@test -n "$(KEY_FILE)" || { echo "KEY_FILE is required" >&2; exit 1; }
	@set -eu; \
	echo "Stopping chatbot for credential rotation..."; \
	$(COMPOSE) stop chatbot; \
	restore_chatbot() { \
		echo "Restoring chatbot service..."; \
		$(COMPOSE) up -d chatbot --pull never --wait >/dev/null || true; \
	}; \
	trap restore_chatbot EXIT HUP INT TERM; \
	CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		python3 -m tools.rotate_auth_key \
		--owner "$(OWNER)" \
		--key-file "$(KEY_FILE)"; \
	$(COMPOSE) up -d chatbot --pull never --wait; \
	trap - EXIT HUP INT TERM; \
	echo "AUTH ROTATION COMPLETE"


.PHONY: smoke-stream

smoke-stream: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 -m tools.smoke_stream


.PHONY: smoke-stream-history

smoke-stream-history: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" 		python3 -m tools.smoke_stream_history


.PHONY: gateway-status gateway-ready smoke-gateway

gateway-status:
	@curl -fsS $(GATEWAY_URL)/live
	@echo


gateway-ready:
	@curl -fsS \
		-X POST \
		$(GATEWAY_URL)/healthcheck/run \
		-H 'Content-Type: application/json' \
		-d '{}'
	@echo


smoke-gateway: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		CHAT_GATEWAY_BASE_URL="$(GATEWAY_URL)" \
		python3 -m tools.smoke_gateway


.PHONY: smoke-gateway-stream smoke-production audit-secrets m7-accept

smoke-gateway-stream: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		CHAT_BASE_URL="$(GATEWAY_URL)" \
		python3 -m tools.smoke_stream


smoke-production: check-auth
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		CHAT_GATEWAY_BASE_URL="$(GATEWAY_URL)" \
		python3 -m tools.smoke_production


audit-secrets:
	@python3 -m tools.audit_runtime_secrets


m7-accept: verify smoke-gateway-stream smoke-production audit-secrets
	@echo
	@echo "M7 ACCEPTANCE PASS"


.PHONY: check-secret-groups bundle bundle-verify

check-secret-groups: check-env
	@python3 -m tools.check_secret_groups


bundle: check-env check-offline-scripts check-secret-groups
	@BUNDLE_VERSION="$(BUNDLE_VERSION)" \
		./tools/build_offline_bundle.sh


bundle-verify:
	@test -n "$(BUNDLE_DIR)" || { \
		echo "BUNDLE_DIR is required" >&2; \
		exit 1; \
	}
	@./tools/verify_offline_bundle.sh "$(BUNDLE_DIR)"


.PHONY: check-offline-scripts

check-offline-scripts:
	@bash -n offline/install.sh
	@bash -n offline/manage.sh
	@bash -n offline/accept.sh
	@bash -n tools/build_offline_bundle.sh
	@bash -n tools/verify_offline_bundle.sh
	@echo "OFFLINE SCRIPT CHECK PASS"
