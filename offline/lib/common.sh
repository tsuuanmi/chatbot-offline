#!/usr/bin/env bash

offline_die() {
    printf 'ERROR: %s\n' "$*" >&2
    return 1
}

offline_require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        offline_die "Required command not found: $1"
}

offline_require_installation() {
    [[ -n "${OFFLINE_ROOT:-}" ]] ||
        offline_die "OFFLINE_ROOT is not configured"

    [[ -f "$OFFLINE_ROOT/.env" ]] ||
        offline_die \
            "Installation is not configured; run offline/install.sh first"

    [[ -f "$OFFLINE_ROOT/versions.env" ]] ||
        offline_die "versions.env is missing"
}

offline_project_name() {
    printf '%s\n' \
        "${CHATBOT_PROJECT_NAME:-chatbot-offline}"
}

offline_compose() {
    env \
        -u LLAMA_GPU_IMAGE \
        -u LLAMA_GPU_LAYERS \
        -u LLAMA_GPU_LAYERS_DRAFT \
        -u LLAMA_SPEC_TYPE \
        -u LLAMA_SPEC_DRAFT_N_MAX \
        -u MTP_MODEL_NAME \
        docker compose \
        --project-directory "$OFFLINE_ROOT" \
        --project-name "$(offline_project_name)" \
        --env-file "$OFFLINE_ROOT/.env" \
        --env-file "$OFFLINE_ROOT/versions.env" \
        "$@"
}

offline_gpu_compose() {
    local addon_dir="$1"
    shift

    env \
        -u LLAMA_GPU_IMAGE \
        -u LLAMA_GPU_LAYERS \
        -u LLAMA_GPU_LAYERS_DRAFT \
        -u LLAMA_SPEC_TYPE \
        -u LLAMA_SPEC_DRAFT_N_MAX \
        -u MTP_MODEL_NAME \
        docker compose \
        --project-directory "$OFFLINE_ROOT" \
        --project-name "$(offline_project_name)" \
        --env-file "$OFFLINE_ROOT/.env" \
        --env-file "$OFFLINE_ROOT/versions.env" \
        --env-file "$addon_dir/versions.gpu.env" \
        -f "$OFFLINE_ROOT/compose.yaml" \
        -f "$OFFLINE_ROOT/compose.gpu.yaml" \
        "$@"
}

offline_manifest_value() {
    local file="$1"
    local key="$2"

    awk -F= \
        -v key="$key" \
        '$1 == key {
            print substr($0, index($0, "=") + 1)
        }' \
        "$file"
}

offline_env_value() {
    local key="$1"

    awk -F= \
        -v key="$key" \
        '$1 == key {
            print substr($0, index($0, "=") + 1)
        }' \
        "$OFFLINE_ROOT/.env"
}

offline_gateway_url() {
    local host
    local port

    host="$(
        offline_env_value GATEWAY_BIND
    )"

    port="$(
        offline_env_value GATEWAY_PORT
    )"

    host="${host:-127.0.0.1}"
    port="${port:-18080}"

    if [[ "$host" == "0.0.0.0" ]]; then
        host="127.0.0.1"
    fi

    printf 'http://%s:%s\n' \
        "$host" \
        "$port"
}

offline_checksum() {
    python3 \
        "$OFFLINE_ROOT/offline/lib/check.py" \
        checksum \
        "$1"
}

offline_verify() {
    python3 \
        "$OFFLINE_ROOT/offline/lib/check.py" \
        runtime \
        "$(offline_gateway_url)" \
        "$OFFLINE_ROOT/runtime/secrets/chat_api_key"
}
