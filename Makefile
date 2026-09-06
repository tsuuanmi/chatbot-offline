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

LLAMA_GPU_LAYERS ?= 99
LLAMA_GPU_LAYERS_DRAFT ?= 99

COMPOSE = env \
	-u CHATBOT_IMAGE \
	-u HAYHOOKS_IMAGE \
	-u LLAMA_CPU_IMAGE \
	-u LLAMA_GPU_IMAGE \
	-u POSTGRES_IMAGE \
	-u NGINX_IMAGE \
	-u EMBEDDING_MODEL \
	-u EMBEDDING_DIMENSION \
	docker compose \
	--env-file $(RUNTIME_ENV) \
	--env-file $(VERSIONS_ENV)

GPU_COMPOSE = $(COMPOSE) \
	-f compose.yaml \
	-f compose.gpu.yaml

TOOLS = $(COMPOSE) --profile tools


.PHONY: \
	help \
	config \
	build \
	up \
	down \
	restart \
	ps \
	logs \
	migrate \
	reindex \
	gpu \
	cpu \
	auth-init \
	auth-check \
	auth-rotate \
	test \
	verify \
	accept \
	bundle \
	bundle-gpu \
	clean


help:
	@printf '%s\n' \
		'chatbot-offline commands' \
		'' \
		'Runtime:' \
		'  make build             Build and pin chatbot image' \
		'  make up                Start CPU stack' \
		'  make gpu               Switch stack to NVIDIA GPU' \
		'  make cpu               Switch stack back to CPU' \
		'  make down              Stop stack' \
		'  make restart           Restart CPU stack' \
		'  make ps                Show services' \
		'  make logs [SERVICE=x]  Show logs' \
		'' \
		'Data:' \
		'  make migrate           Apply database migrations' \
		'  make reindex           Rebuild knowledge index' \
		'' \
		'Auth:' \
		'  make auth-init' \
		'  make auth-check' \
		'  make auth-rotate OWNER=x KEY_FILE=path' \
		'' \
		'Quality:' \
		'  make test              Run unit tests' \
		'  make verify            Common runtime acceptance' \
		'  make accept            Full release acceptance' \
		'' \
		'Release:' \
		'  make bundle [BUNDLE_VERSION=x]' \
		'  make bundle-gpu [BUNDLE_VERSION=x]'


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
	@$(COMPOSE) config --quiet
	@echo "COMPOSE CONFIG PASS"


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
	image_id="$$( \
		docker image inspect \
			"$(APP_TAG)" \
			--format '{{.Id}}' \
	)"; \
	sed -i '/^CHATBOT_IMAGE=/d' "$(VERSIONS_ENV)"; \
	printf 'CHATBOT_IMAGE=%s\n' "$$image_id" \
		>> "$(VERSIONS_ENV)"; \
	echo "CHATBOT_IMAGE=$$image_id"


up: check-env auth-check
	@$(COMPOSE) up \
		-d \
		--pull never \
		--wait


down: check-env
	@$(COMPOSE) down


restart: down up


ps: check-env
	@$(COMPOSE) ps


logs: check-env
	@$(COMPOSE) logs \
		--tail=$${LINES:-200} \
		$(if $(SERVICE),$(SERVICE),)


migrate: check-env
	@$(TOOLS) run \
		--rm \
		db-migrate


reindex: check-env
	@echo "Stopping client-facing services..."
	@$(COMPOSE) stop proxy chatbot
	@$(COMPOSE) up \
		-d \
		postgres \
		--pull never \
		--wait
	@$(TOOLS) run \
		--rm \
		index-knowledge
	@$(COMPOSE) up \
		-d \
		chatbot \
		proxy \
		--pull never \
		--wait
	@echo "REINDEX PASS"


gpu: check-env auth-check
	@LLAMA_GPU_LAYERS="$(LLAMA_GPU_LAYERS)" \
		LLAMA_GPU_LAYERS_DRAFT="$(LLAMA_GPU_LAYERS_DRAFT)" \
		$(GPU_COMPOSE) up \
			-d \
			--pull never \
			--force-recreate \
			--wait \
			llama-server
	@LLAMA_GPU_LAYERS="$(LLAMA_GPU_LAYERS)" \
		LLAMA_GPU_LAYERS_DRAFT="$(LLAMA_GPU_LAYERS_DRAFT)" \
		$(GPU_COMPOSE) up \
			-d \
			--pull never \
			--wait
	@CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 -m tools.accept full --gpu


cpu: check-env auth-check
	@$(COMPOSE) up \
		-d \
		--pull never \
		--force-recreate \
		--wait \
		llama-server
	@$(COMPOSE) up \
		-d \
		--pull never \
		--wait


auth-init:
	@CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 -m tools.auth init


auth-check:
	@CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		python3 -m tools.auth check


auth-rotate: check-env
	@test -n "$(OWNER)" || { \
		echo "OWNER is required" >&2; \
		exit 1; \
	}
	@test -n "$(KEY_FILE)" || { \
		echo "KEY_FILE is required" >&2; \
		exit 1; \
	}
	@set -eu; \
	echo "Stopping chatbot for credential rotation..."; \
	$(COMPOSE) stop chatbot; \
	restore_chatbot() { \
		$(COMPOSE) up \
			-d \
			chatbot \
			--pull never \
			--wait \
			>/dev/null \
			|| true; \
	}; \
	trap restore_chatbot EXIT HUP INT TERM; \
	CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		python3 -m tools.auth rotate \
			--owner "$(OWNER)" \
			--key-file "$(KEY_FILE)"; \
	$(COMPOSE) up \
		-d \
		chatbot \
		--pull never \
		--wait; \
	trap - EXIT HUP INT TERM; \
	echo "AUTH ROTATION PASS"


test:
	@python3 -m unittest \
		discover \
		-s tests/unit \
		-t . \
		-p 'test_*.py' \
		-v


verify: check-env
	@CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		CHAT_GATEWAY_BASE_URL="$(GATEWAY_URL)" \
		python3 -m tools.accept verify


accept: check-env
	@CHAT_AUTH_REGISTRY_PATH="$(AUTH_REGISTRY)" \
		CHAT_CLIENT_API_KEY_FILE="$(CLIENT_API_KEY)" \
		CHAT_GATEWAY_BASE_URL="$(GATEWAY_URL)" \
		python3 -m tools.accept full


bundle: check-env
	@python3 -m tools.release build cpu \
		$(if $(BUNDLE_VERSION),--version "$(BUNDLE_VERSION)",)


bundle-gpu: check-env
	@python3 -m tools.release build gpu \
		$(if $(BUNDLE_VERSION),--version "$(BUNDLE_VERSION)",)


clean:
	@rm -f /tmp/chatbot-offline-*.json
