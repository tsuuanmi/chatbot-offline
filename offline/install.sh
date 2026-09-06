#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

cd "$ROOT"

export OFFLINE_ROOT="$ROOT"

source "$ROOT/offline/lib/common.sh"
source "$ROOT/offline/lib/gpu.sh"

log() {
    printf '[install] %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command not found: $1"
}

if [[ "${EUID}" -eq 0 ]]; then
    die \
        "Run installer as the deployment user with Docker access, not as root"
fi

for command in \
    docker \
    python3 \
    sha256sum
do
    require_command "$command"
done

docker info >/dev/null 2>&1 ||
    die \
        "Docker daemon is unavailable for this user"

docker compose version >/dev/null 2>&1 ||
    die \
        "Docker Compose plugin is unavailable"

[[ -f SHA256SUMS ]] ||
    die "SHA256SUMS is missing"

[[ -f BUNDLE-MANIFEST.txt ]] ||
    die "BUNDLE-MANIFEST.txt is missing"

BUNDLE_TYPE="$(
    offline_manifest_value \
        BUNDLE-MANIFEST.txt \
        bundle_type
)"

[[ "$BUNDLE_TYPE" == "universal" ]] ||
    die \
        "Only universal runtime releases are supported"

log "Verifying runtime release"
sha256sum -c SHA256SUMS >/dev/null

BUNDLE_ARCH="$(
    offline_manifest_value \
        BUNDLE-MANIFEST.txt \
        architecture
)"

if [[ -n "$BUNDLE_ARCH" ]] &&
   [[ "$BUNDLE_ARCH" != "$(uname -m)" ]]
then
    die \
        "Bundle architecture $BUNDLE_ARCH does not match host $(uname -m)"
fi

if [[ -f /etc/os-release ]]; then
    source /etc/os-release

    case "${ID:-}" in
        rhel|rocky|almalinux|centos)
            require_command getenforce

            SELINUX_MODE="$(
                getenforce
            )"

            [[ "$SELINUX_MODE" == "Enforcing" ]] ||
                die \
                    "RHEL-compatible production deployment requires SELinux Enforcing"

            log \
                "SELinux Enforcing detected"
            ;;
    esac
fi

log "Loading offline runtime images"

for archive in \
    images/chatbot.tar \
    images/llama-cpu.tar \
    images/llama-gpu.tar \
    images/postgres.tar \
    images/nginx.tar
do
    [[ -f "$archive" ]] ||
        die \
            "Missing image archive: $archive"

    docker load \
        -i "$archive" \
        >/dev/null

    log \
        "Loaded $archive"
done

set -a
source versions.env
source versions.gpu.env
set +a

for variable in \
    CHATBOT_IMAGE \
    LLAMA_CPU_IMAGE \
    LLAMA_GPU_IMAGE \
    POSTGRES_IMAGE \
    NGINX_IMAGE
do
    value="${!variable:-}"

    [[ -n "$value" ]] ||
        die \
            "$variable is missing from release configuration"

    docker image inspect \
        "$value" \
        >/dev/null ||
        die \
            "Loaded image is unavailable: $value"
done

log "Runtime image verification passed"

if [[ ! -f .env ]]; then
    cp \
        .env.example \
        .env

    chmod 600 .env

    log \
        "Created .env from .env.example"
fi

MODEL_STORE="${CHATBOT_MODEL_STORE:-$HOME/.local/share/chatbot/models}"

STATE_DIR="${CHATBOT_STATE_DIR:-$HOME/.local/share/chatbot/state}"

mkdir -p "$STATE_DIR"

INSTALL_RUNTIME_DIR="$(cd "$STATE_DIR" && pwd)"

MODEL_PACKAGE="${CHATBOT_MODEL_PACKAGE:-}"

log \
    "Resolving model bundle"

MODEL_OUTPUT="$(
    python3 \
        "$ROOT/offline/lib/models.py" \
        install \
        --root "$ROOT" \
        --store "$MODEL_STORE" \
        --package "$MODEL_PACKAGE"
)"

printf '%s\n' \
    "$MODEL_OUTPUT"

INSTALL_MODEL_DIR="$(
    printf '%s\n' \
        "$MODEL_OUTPUT" \
    | awk -F= '
        $1 == "MODEL_DIR" {
            print substr($0, index($0, "=") + 1)
        }
    ' \
    | tail -n 1
)"

[[ -n "$INSTALL_MODEL_DIR" ]] ||
    die \
        "Model installer did not return MODEL_DIR"

INSTALL_ACCELERATOR="${CHATBOT_ACCELERATOR:-auto}"

case "$INSTALL_ACCELERATOR" in
    auto)
        if offline_gpu_available; then
            INSTALL_ACCELERATOR="gpu"

            log \
                "NVIDIA GPU detected; selecting GPU runtime"
        else
            INSTALL_ACCELERATOR="cpu"

            log \
                "NVIDIA GPU unavailable; selecting CPU runtime"
        fi
        ;;

    cpu)
        log \
            "CPU runtime explicitly selected"
        ;;

    gpu)
        offline_gpu_available ||
            die \
                "GPU mode requested but NVIDIA GPU is unavailable to Docker"

        log \
            "GPU runtime explicitly selected"
        ;;

    *)
        die \
            "Invalid accelerator: $INSTALL_ACCELERATOR; expected auto, cpu, or gpu"
        ;;
esac

SECRET_GID="$(
    id -g
)"

INSTALL_GATEWAY_BIND="${GATEWAY_BIND:-0.0.0.0}"

INSTALL_GATEWAY_PORT="${GATEWAY_PORT:-18080}"

python3 - \
    "$ROOT/.env" \
    "$SECRET_GID" \
    "$INSTALL_GATEWAY_BIND" \
    "$INSTALL_GATEWAY_PORT" \
    "$INSTALL_MODEL_DIR" \
    "$INSTALL_RUNTIME_DIR" \
    "$INSTALL_ACCELERATOR" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

values = {
    "CHATBOT_SECRET_GID": sys.argv[2],
    "GATEWAY_BIND": sys.argv[3],
    "GATEWAY_PORT": sys.argv[4],
    "MODEL_DIR": sys.argv[5],
    "CHATBOT_RUNTIME_DIR": sys.argv[6],
    "CHATBOT_ACCELERATOR": sys.argv[7],
}

lines = path.read_text(
    encoding="utf-8"
).splitlines()

found = set()
output = []

for line in lines:
    key = line.partition("=")[0]

    if key in values:
        output.append(
            f"{key}={values[key]}"
        )
        found.add(key)
    else:
        output.append(line)

for key, value in values.items():
    if key not in found:
        output.append(
            f"{key}={value}"
        )

path.write_text(
    "\n".join(output) + "\n",
    encoding="utf-8",
)
PY

chmod 600 .env

set -a
source .env
source versions.env
set +a

: "${MODEL_DIR:?MODEL_DIR is required}"
: "${LLAMA_MODEL_NAME:?LLAMA_MODEL_NAME is required}"
: "${MTP_MODEL_NAME:?MTP_MODEL_NAME is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${CHATBOT_RUNTIME_DIR:?CHATBOT_RUNTIME_DIR is required}"

SECRETS_DIR="${CHATBOT_RUNTIME_DIR}/secrets"

[[ -f "${MODEL_DIR}/${LLAMA_MODEL_NAME}" ]] ||
    die \
        "Main model is missing: ${MODEL_DIR}/${LLAMA_MODEL_NAME}"

[[ -f "${MODEL_DIR}/${MTP_MODEL_NAME}" ]] ||
    die \
        "MTP model is missing: ${MODEL_DIR}/${MTP_MODEL_NAME}"

PROJECT_NAME="chatbot"

mkdir -p "$SECRETS_DIR"

chmod 700 "$SECRETS_DIR"

required_secrets=(
    "$SECRETS_DIR/chat_auth.json"
    "$SECRETS_DIR/chat_api_key"
    "$SECRETS_DIR/llama_api_key"
    "$SECRETS_DIR/postgres_password"
)

existing=0

for path in "${required_secrets[@]}"; do
    if [[ -e "$path" ]]; then
        existing=$((existing + 1))
    fi
done

if (( existing != 0 && existing != ${#required_secrets[@]} )); then
    die \
        "Partial secret configuration detected; refusing to regenerate credentials"
fi

if (( existing == 0 )); then
    POSTGRES_VOLUME="$(
        docker volume ls \
            --quiet \
            --filter \
                "label=com.docker.compose.project=${PROJECT_NAME}" \
            --filter \
                "label=com.docker.compose.volume=postgres_data" \
        | head -n 1
    )"

    if [[ -n "$POSTGRES_VOLUME" ]]; then
        die \
            "PostgreSQL data exists for project ${PROJECT_NAME}, but runtime secrets are missing"
    fi

    INSTALL_OWNER="${CHAT_OWNER_ID:-local-user}"

    log \
        "Generating local credentials"

    umask 077

    python3 - \
        "$INSTALL_OWNER" \
        "$SECRETS_DIR" <<'PY'
from __future__ import annotations

import hashlib
import json
import re
import secrets
import sys
from pathlib import Path

owner = sys.argv[1]

if not re.fullmatch(
    r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}",
    owner,
):
    raise SystemExit(
        "Invalid CHAT_OWNER_ID"
    )

root = Path(
    sys.argv[2]
)

client_key = secrets.token_urlsafe(
    32
)

llama_key = secrets.token_urlsafe(
    32
)

postgres_password = secrets.token_urlsafe(
    32
)

registry = {
    "version": 1,
    "identities": [
        {
            "owner_id": owner,
            "api_key_sha256": hashlib.sha256(
                client_key.encode(
                    "utf-8"
                )
            ).hexdigest(),
        }
    ],
}

(root / "chat_api_key").write_text(
    client_key + "\n",
    encoding="utf-8",
)

(root / "llama_api_key").write_text(
    llama_key + "\n",
    encoding="utf-8",
)

(root / "postgres_password").write_text(
    postgres_password + "\n",
    encoding="utf-8",
)

(root / "chat_auth.json").write_text(
    json.dumps(
        registry,
        indent=2,
        sort_keys=True,
    )
    + "\n",
    encoding="utf-8",
)
PY
fi

chgrp "$SECRET_GID" \
    "$SECRETS_DIR/chat_auth.json" \
    "$SECRETS_DIR/llama_api_key" \
    "$SECRETS_DIR/postgres_password"

chmod 640 \
    "$SECRETS_DIR/chat_auth.json" \
    "$SECRETS_DIR/llama_api_key" \
    "$SECRETS_DIR/postgres_password"

chmod 600 \
    "$SECRETS_DIR/chat_api_key"

log "Stopping previous chatbot runtime"

mapfile -t OLD_CONTAINERS < <(
    docker ps -aq \
        --filter "label=com.docker.compose.project=chatbot"
)

if (( ${#OLD_CONTAINERS[@]} > 0 )); then
    docker rm -f \
        "${OLD_CONTAINERS[@]}" \
        >/dev/null
fi

docker network rm \
    chatbot_default \
    >/dev/null 2>&1 \
    || true

log \
    "Validating Compose configuration"

offline_runtime_compose \
    config \
    >/dev/null

log \
    "Starting PostgreSQL"

offline_compose \
    up \
    -d \
    postgres \
    --pull never \
    --wait

log \
    "Applying database migrations"

offline_compose \
    --profile tools \
    run \
    --rm \
    db-migrate

log \
    "Building knowledge index"

offline_compose \
    --profile tools \
    run \
    --rm \
    index-knowledge

log \
    "Starting ${INSTALL_ACCELERATOR^^} llama.cpp"

offline_runtime_compose \
    up \
    -d \
    llama-server \
    --pull never \
    --force-recreate \
    --wait

log \
    "Updating configured figure cache"

offline_compose \
    --profile tools \
    run \
    --rm \
    --no-deps \
    index-figures
log \
    "Starting chatbot and Nginx"

offline_runtime_compose \
    up \
    -d \
    chatbot \
    proxy \
    --pull never \
    --wait

log \
    "Verifying installed deployment"

offline_verify

HOST_IP="$(
    offline_detect_host_ip
)"

PORT="${GATEWAY_PORT:-18080}"

log "Removing superseded chatbot image versions"

CURRENT_IMAGES=(
    "$CHATBOT_IMAGE"
    "$LLAMA_CPU_IMAGE"
    "$LLAMA_GPU_IMAGE"
    "$POSTGRES_IMAGE"
    "$NGINX_IMAGE"
)

for repository in \
    chatbot-app \
    chatbot-llama-cpu \
    chatbot-llama-gpu \
    chatbot-postgres \
    chatbot-nginx
do
    while IFS= read -r image; do
        [[ -n "$image" ]] || continue

        keep=false

        for current in "${CURRENT_IMAGES[@]}"; do
            if [[ "$image" == "$current" ]]; then
                keep=true
                break
            fi
        done

        if [[ "$keep" == false ]]; then
            docker image rm \
                "$image" \
                >/dev/null 2>&1 \
                || true
        fi
    done < <(
        docker image ls \
            "$repository" \
            --format '{{.Repository}}:{{.Tag}}'
    )
done

echo

log \
    "OFFLINE INSTALL PASS"

log \
    "accelerator=$INSTALL_ACCELERATOR"

log \
    "local=http://127.0.0.1:${PORT}"

log \
    "network=http://${HOST_IP}:${PORT}"

log \
    "project=chatbot"

log \
    "models=$MODEL_DIR"
