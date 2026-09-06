#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

cd "$ROOT"

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
    die "Run installer as the deployment user with Docker access, not as root"
fi

for command in \
    docker \
    python3 \
    sha256sum
do
    require_command "$command"
done

docker info >/dev/null 2>&1 ||
    die "Docker daemon is unavailable for this user"

docker compose version >/dev/null 2>&1 ||
    die "Docker Compose plugin is unavailable"

[[ -f SHA256SUMS ]] ||
    die "SHA256SUMS is missing"

[[ -f BUNDLE-MANIFEST.txt ]] ||
    die "BUNDLE-MANIFEST.txt is missing"

log "Verifying offline bundle"
sha256sum -c SHA256SUMS >/dev/null

BUNDLE_ARCH="$(
    awk -F= '
        $1 == "architecture" {
            print substr($0, index($0, "=") + 1)
        }
    ' BUNDLE-MANIFEST.txt
)"

if [[ -n "$BUNDLE_ARCH" ]] &&
   [[ "$BUNDLE_ARCH" != "$(uname -m)" ]]
then
    die \
        "Bundle architecture $BUNDLE_ARCH does not match host $(uname -m)"
fi

if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release

    case "${ID:-}" in
        rhel|rocky|almalinux|centos)
            require_command getenforce

            SELINUX_MODE="$(getenforce)"

            [[ "$SELINUX_MODE" == "Enforcing" ]] ||
                die \
                    "RHEL-compatible production deployment requires SELinux Enforcing"

            log "SELinux Enforcing detected"
            ;;
    esac
fi

log "Loading runtime images"

for archive in \
    images/chatbot.tar \
    images/llama-cpu.tar \
    images/postgres.tar \
    images/nginx.tar
do
    [[ -f "$archive" ]] ||
        die "Missing image archive: $archive"

    docker load -i "$archive" >/dev/null

    log "Loaded $archive"
done

set -a
# shellcheck disable=SC1091
source versions.env
set +a

for variable in \
    CHATBOT_IMAGE \
    LLAMA_CPU_IMAGE \
    POSTGRES_IMAGE \
    NGINX_IMAGE
do
    value="${!variable:-}"

    [[ -n "$value" ]] ||
        die "$variable is missing from versions.env"

    docker image inspect "$value" >/dev/null ||
        die "Loaded image is unavailable: $value"
done

log "Runtime image verification passed"

if [[ ! -f .env ]]; then
    cp .env.example .env
    chmod 600 .env
    log "Created .env from .env.example"
fi

SECRET_GID="$(id -g)"
INSTALL_GATEWAY_BIND="${GATEWAY_BIND:-127.0.0.1}"
INSTALL_GATEWAY_PORT="${GATEWAY_PORT:-18080}"

python3 - \
    "$SECRET_GID" \
    "$INSTALL_GATEWAY_BIND" \
    "$INSTALL_GATEWAY_PORT" <<'PY'
from pathlib import Path
import sys

path = Path(".env")

values = {
    "CHATBOT_SECRET_GID": sys.argv[1],
    "GATEWAY_BIND": sys.argv[2],
    "GATEWAY_PORT": sys.argv[3],
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

set -a
# shellcheck disable=SC1091
source .env
# shellcheck disable=SC1091
source versions.env
set +a

: "${MODEL_DIR:?MODEL_DIR is required}"
: "${LLAMA_MODEL_NAME:?LLAMA_MODEL_NAME is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"

[[ -f "${MODEL_DIR}/${LLAMA_MODEL_NAME}" ]] ||
    die \
        "Bundled model is missing: ${MODEL_DIR}/${LLAMA_MODEL_NAME}"

PROJECT_NAME="${CHATBOT_PROJECT_NAME:-chatbot-offline}"

mkdir -p runtime/secrets
chmod 700 runtime/secrets

required_secrets=(
    runtime/secrets/chat_auth.json
    runtime/secrets/chat_api_key
    runtime/secrets/llama_api_key
    runtime/secrets/postgres_password
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
        docker volume ls             --quiet             --filter "label=com.docker.compose.project=${PROJECT_NAME}"             --filter "label=com.docker.compose.volume=postgres_data"         | head -n 1
    )"

    if [[ -n "$POSTGRES_VOLUME" ]]; then
        die             "PostgreSQL data exists for project ${PROJECT_NAME}, but runtime secrets are missing; restore the original secrets or remove the old data volume for a fresh installation"
    fi

    INSTALL_OWNER="${CHAT_OWNER_ID:-local-user}"

    log "Generating local credentials"

    umask 077

    python3 - "$INSTALL_OWNER" <<'PY'
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
    "runtime/secrets"
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
    runtime/secrets/chat_auth.json \
    runtime/secrets/llama_api_key \
    runtime/secrets/postgres_password

chmod 640 \
    runtime/secrets/chat_auth.json \
    runtime/secrets/llama_api_key \
    runtime/secrets/postgres_password

chmod 600 \
    runtime/secrets/chat_api_key


compose() {
    docker compose \
        --project-directory "$ROOT" \
        --project-name "$PROJECT_NAME" \
        --env-file "$ROOT/.env" \
        --env-file "$ROOT/versions.env" \
        "$@"
}

log "Validating Compose configuration"
compose config >/dev/null

log "Starting PostgreSQL"
compose up \
    -d \
    postgres \
    --pull never \
    --wait

log "Applying database migrations"
compose \
    --profile tools \
    run \
    --rm \
    db-migrate

log "Building knowledge index"
compose \
    --profile tools \
    run \
    --rm \
    index-knowledge

log "Starting llama.cpp"
compose up \
    -d \
    llama-server \
    --pull never \
    --wait

log "Starting chatbot and Nginx"
compose up \
    -d \
    chatbot \
    proxy \
    --pull never \
    --wait

log "Verifying installed deployment"

"$ROOT/offline/manage.sh" verify

echo
log "OFFLINE INSTALL PASS"
log "gateway=$(
    GATEWAY_BIND="$GATEWAY_BIND"     GATEWAY_PORT="$GATEWAY_PORT"     "$ROOT/offline/manage.sh" gateway-url
)"
log "project=${PROJECT_NAME}"
