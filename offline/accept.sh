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

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command not found: $1"
}

for command in \
    docker \
    python3 \
    sha256sum
do
    require_command "$command"
done

docker info >/dev/null 2>&1 ||
    die "Docker daemon is unavailable"

docker compose version >/dev/null 2>&1 ||
    die "Docker Compose plugin is unavailable"

[[ -f .env ]] ||
    die ".env is missing"

[[ -f versions.env ]] ||
    die "versions.env is missing"

[[ -f BUNDLE-MANIFEST.txt ]] ||
    die "BUNDLE-MANIFEST.txt is missing"

PROJECT_NAME="${CHATBOT_PROJECT_NAME:-chatbot-offline}"

compose() {
    docker compose \
        --project-directory "$ROOT" \
        --project-name "$PROJECT_NAME" \
        --env-file "$ROOT/.env" \
        --env-file "$ROOT/versions.env" \
        "$@"
}

ARCHITECTURE="$(
    awk -F= '
        $1 == "architecture" {
            print substr($0, index($0, "=") + 1)
        }
    ' BUNDLE-MANIFEST.txt
)"

[[ -n "$ARCHITECTURE" ]] ||
    die "Bundle architecture is missing"

[[ "$ARCHITECTURE" == "$(uname -m)" ]] ||
    die \
        "Bundle architecture ${ARCHITECTURE} does not match host $(uname -m)"

echo "PASS architecture=${ARCHITECTURE}"

[[ -f /etc/os-release ]] ||
    die "/etc/os-release is missing"

# shellcheck disable=SC1091
source /etc/os-release

case "${ID:-}" in
    ubuntu)
        echo "PASS platform=ubuntu"
        ;;

    rhel|rocky|almalinux|centos)
        require_command getenforce

        SELINUX_MODE="$(getenforce)"

        [[ "$SELINUX_MODE" == "Enforcing" ]] ||
            die \
                "RHEL-compatible deployment requires SELinux Enforcing"

        echo "PASS platform=${ID} selinux=Enforcing"
        ;;

    *)
        die \
            "Unsupported acceptance platform: ${ID:-unknown}"
        ;;
esac

compose config >/dev/null

echo "PASS compose configuration"

for service in \
    postgres \
    llama-server \
    chatbot \
    proxy
do
    container_id="$(
        compose ps -q "$service"
    )"

    [[ -n "$container_id" ]] ||
        die "Service is not running: $service"

    status="$(
        docker inspect \
            --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
            "$container_id"
    )"

    [[ "$status" == "healthy" ]] ||
        die \
            "Service is not healthy: ${service} status=${status}"

    echo "PASS service=${service} status=${status}"
done

CHATBOT_ID="$(
    compose ps -q chatbot
)"

CHATBOT_USER="$(
    docker inspect \
        --format '{{.Config.User}}' \
        "$CHATBOT_ID"
)"

[[ "$CHATBOT_USER" == "10001:10001" ]] ||
    die \
        "Unexpected chatbot user: ${CHATBOT_USER}"

echo "PASS chatbot non-root user=${CHATBOT_USER}"

CHATBOT_READONLY="$(
    docker inspect \
        --format '{{.HostConfig.ReadonlyRootfs}}' \
        "$CHATBOT_ID"
)"

[[ "$CHATBOT_READONLY" == "true" ]] ||
    die "Chatbot root filesystem is not read-only"

echo "PASS chatbot read-only filesystem"

PROXY_ID="$(
    compose ps -q proxy
)"

PROXY_READONLY="$(
    docker inspect \
        --format '{{.HostConfig.ReadonlyRootfs}}' \
        "$PROXY_ID"
)"

[[ "$PROXY_READONLY" == "true" ]] ||
    die "Proxy root filesystem is not read-only"

echo "PASS proxy read-only filesystem"

CHATBOT_PORT_BINDINGS="$(
    docker inspect \
        --format '{{json .HostConfig.PortBindings}}' \
        "$CHATBOT_ID"
)"

python3 - \
    "$CHATBOT_PORT_BINDINGS" <<'PY_PORTS'
import json
import sys

bindings = json.loads(
    sys.argv[1]
)

published = bindings.get(
    "1416/tcp"
)

if published:
    raise SystemExit(
        "Production chatbot port 1416 is published"
    )

print(
    "PASS chatbot private network boundary"
)
PY_PORTS

"$ROOT/offline/manage.sh" verify

echo
echo "M8 PLATFORM ACCEPTANCE PASS"
