#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

cd "$ROOT"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f .env ]] ||
    die "Installation is not configured; run offline/install.sh first"

[[ -f versions.env ]] ||
    die "versions.env is missing"

PROJECT_NAME="${CHATBOT_PROJECT_NAME:-chatbot-offline}"

compose() {
    docker compose \
        --project-directory "$ROOT" \
        --project-name "$PROJECT_NAME" \
        --env-file "$ROOT/.env" \
        --env-file "$ROOT/versions.env" \
        "$@"
}

start_stack() {
    compose up \
        -d \
        --pull never \
        --wait

    echo "OFFLINE START PASS"
}

stop_stack() {
    compose down

    echo "OFFLINE STOP PASS"
}

status_stack() {
    compose ps
}

logs_stack() {
    local service="${1:-chatbot}"

    compose logs \
        --tail="${TAIL:-200}" \
        -f \
        "$service"
}

reindex_stack() {
    echo "Stopping client-facing services..."

    compose stop proxy chatbot

    restore_services() {
        compose up \
            -d \
            chatbot \
            proxy \
            --pull never \
            --wait \
            >/dev/null 2>&1 \
            || true
    }

    trap restore_services EXIT HUP INT TERM

    compose up \
        -d \
        postgres \
        --pull never \
        --wait

    compose \
        --profile tools \
        run \
        --rm \
        index-knowledge

    compose up \
        -d \
        chatbot \
        proxy \
        --pull never \
        --wait

    trap - EXIT HUP INT TERM

    echo "OFFLINE REINDEX PASS"
}

verify_stack() {
    set -a
    # shellcheck disable=SC1091
    source "$ROOT/.env"
    set +a

    local gateway_host="${GATEWAY_BIND:-127.0.0.1}"
    local gateway_port="${GATEWAY_PORT:-18080}"

    if [[ "$gateway_host" == "0.0.0.0" ]]; then
        gateway_host="127.0.0.1"
    fi

    local gateway_url="http://${gateway_host}:${gateway_port}"

    python3 - \
        "$gateway_url" \
        "$ROOT/runtime/secrets/chat_api_key" <<'PY_VERIFY'
from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path


base = sys.argv[1].rstrip("/")
key_path = Path(sys.argv[2])

if not key_path.is_file():
    raise RuntimeError(
        "client API key is missing"
    )

api_key = key_path.read_text(
    encoding="utf-8"
).strip()

with urllib.request.urlopen(
    base + "/live",
    timeout=10,
) as response:
    if response.status != 200:
        raise RuntimeError(
            f"liveness returned {response.status}"
        )

request = urllib.request.Request(
    base + "/healthcheck/run",
    data=b"{}",
    headers={
        "Content-Type": "application/json",
    },
    method="POST",
)

with urllib.request.urlopen(
    request,
    timeout=30,
) as response:
    body = json.load(response)

    result = body.get("result")

    if not isinstance(result, dict):
        raise RuntimeError(
            "invalid readiness response"
        )

    if result.get("status") != "ready":
        raise RuntimeError(
            f"service is not ready: {result}"
        )

request = urllib.request.Request(
    base + "/chat/run",
    data=json.dumps(
        {
            "message": (
                "Hướng dẫn tôi nấu phở."
            )
        }
    ).encode("utf-8"),
    headers={
        "Content-Type": "application/json",
        "Authorization": (
            "Bearer " + api_key
        ),
    },
    method="POST",
)

with urllib.request.urlopen(
    request,
    timeout=120,
) as response:
    body = json.load(response)

    if response.status != 200:
        raise RuntimeError(
            f"chat returned {response.status}"
        )

    if not isinstance(
        body.get("result"),
        dict,
    ):
        raise RuntimeError(
            "invalid authenticated chat response"
        )

print("OFFLINE VERIFY PASS")
PY_VERIFY
}

case "${1:-}" in
    start)
        start_stack
        ;;

    stop)
        stop_stack
        ;;

    status)
        status_stack
        ;;

    logs)
        logs_stack "${2:-chatbot}"
        ;;

    reindex)
        reindex_stack
        ;;

    verify)
        verify_stack
        ;;

    *)
        echo \
            "usage: $0 {start|stop|status|logs [service]|reindex|verify}" \
            >&2
        exit 2
        ;;
esac
