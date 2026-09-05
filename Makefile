SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

.DEFAULT_GOAL := help

VERSIONS_ENV ?= versions.env
RUNTIME_ENV ?= .env
APP_TAG ?= chatbot-offline/app:local

COMPOSE = docker compose \
	--env-file $(VERSIONS_ENV) \
	--env-file $(RUNTIME_ENV)

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


up: check-env
	@$(COMPOSE) up -d --pull never --wait


up-recreate: check-env
	@$(COMPOSE) up \
		-d \
		--pull never \
		--force-recreate \
		--wait


down: check-env
	@$(COMPOSE) down


restart: down up


offline-restart: down
	@$(COMPOSE) up -d --pull never --wait
	@echo "OFFLINE RESTART OK"


ps: check-env
	@$(COMPOSE) ps


status:
	@curl -fsS http://127.0.0.1:1416/status
	@echo


health: ps status


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


test-policy:
	@python3 tools/test_domain_policy.py \
		tests/data/domain_calibration.json
	@python3 tools/test_domain_policy.py \
		tests/data/domain_boundary_calibration.json


smoke-m5c:
	@python3 tools/smoke_m5c.py


check-python: check-env
	@$(COMPOSE) exec -T chatbot \
		python -c "from pathlib import Path; roots=[Path('/app/chatbot_app'),Path('/app/pipelines')]; files=sorted(p for root in roots for p in root.rglob('*.py')); [compile(p.read_text(encoding='utf-8'),str(p),'exec') for p in files]; print(f'PYTHON COMPILE OK ({len(files)} files)')"


verify: config health test-policy smoke-m5c check-python
	@echo
	@echo "VERIFY PASS"


clean:
	@rm -f /tmp/chatbot-offline-*.json

.PHONY: stop-llama start-llama

stop-llama: check-env
	@$(COMPOSE) stop llama-server

start-llama: check-env
	@$(COMPOSE) up -d llama-server --pull never --wait
