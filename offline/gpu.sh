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

[[ -f compose.gpu.yaml ]] ||
    die "compose.gpu.yaml is missing"

PROJECT_NAME="${CHATBOT_PROJECT_NAME:-chatbot-offline}"

base_compose() {
    env \
        -u LLAMA_GPU_IMAGE \
        -u LLAMA_GPU_LAYERS \
        docker compose \
        --project-directory "$ROOT" \
        --project-name "$PROJECT_NAME" \
        --env-file "$ROOT/.env" \
        --env-file "$ROOT/versions.env" \
        "$@"
}

gpu_compose() {
    local addon_dir="$1"
    shift

    env \
        -u LLAMA_GPU_IMAGE \
        -u LLAMA_GPU_LAYERS \
        docker compose \
        --project-directory "$ROOT" \
        --project-name "$PROJECT_NAME" \
        --env-file "$ROOT/.env" \
        --env-file "$ROOT/versions.env" \
        --env-file "$addon_dir/versions.gpu.env" \
        -f "$ROOT/compose.yaml" \
        -f "$ROOT/compose.gpu.yaml" \
        "$@"
}

manifest_value() {
    local file="$1"
    local key="$2"

    awk -F= \
        -v key="$key" \
        '$1 == key {print substr($0, index($0, "=") + 1)}' \
        "$file"
}

verify_addon_compatibility() {
    local addon_dir="$1"

    [[ -f BUNDLE-MANIFEST.txt ]] ||
        die "Base bundle manifest is missing"

    [[ -f "$addon_dir/GPU-MANIFEST.txt" ]] ||
        die "GPU add-on manifest is missing"

    local base_sha
    local addon_sha
    local base_arch
    local addon_arch
    local base_version
    local addon_version

    base_sha="$(
        manifest_value \
            BUNDLE-MANIFEST.txt \
            source_git_sha
    )"

    addon_sha="$(
        manifest_value \
            "$addon_dir/GPU-MANIFEST.txt" \
            source_git_sha
    )"

    base_arch="$(
        manifest_value \
            BUNDLE-MANIFEST.txt \
            architecture
    )"

    addon_arch="$(
        manifest_value \
            "$addon_dir/GPU-MANIFEST.txt" \
            architecture
    )"

    base_version="$(
        manifest_value \
            BUNDLE-MANIFEST.txt \
            bundle_version
    )"

    addon_version="$(
        manifest_value \
            "$addon_dir/GPU-MANIFEST.txt" \
            bundle_version
    )"

    [[ "$base_sha" == "$addon_sha" ]] ||
        die "GPU add-on source commit does not match base bundle"

    [[ "$base_arch" == "$addon_arch" ]] ||
        die "GPU add-on architecture does not match base bundle"

    [[ "$base_version" == "$addon_version" ]] ||
        die "GPU add-on version does not match base bundle"
}

verify_gpu_runtime() {
    local addon_dir="$1"

    local cid
    local expected_image
    local running_id
    local expected_id
    local requests
    local devices

    cid="$(
        gpu_compose \
            "$addon_dir" \
            ps -q llama-server
    )"

    [[ -n "$cid" ]] ||
        die "llama-server is not running"

    requests="$(
        docker inspect \
            "$cid" \
            --format '{{json .HostConfig.DeviceRequests}}'
    )"

    [[ "$requests" != "null" ]] ||
        die "llama-server has no GPU device request"

    expected_image="$(
        awk -F= \
            '$1 == "LLAMA_GPU_IMAGE" {print substr($0, index($0, "=") + 1)}' \
            "$addon_dir/versions.gpu.env"
    )"

    [[ -n "$expected_image" ]] ||
        die "LLAMA_GPU_IMAGE is missing"

    running_id="$(
        docker inspect \
            "$cid" \
            --format '{{.Image}}'
    )"

    expected_id="$(
        docker image inspect \
            "$expected_image" \
            --format '{{.Id}}'
    )"

    [[ "$running_id" == "$expected_id" ]] ||
        die "llama-server is not using the GPU image"

    devices="$(
        docker exec \
            "$cid" \
            /app/llama-server \
            --list-devices
    )"

    printf '%s\n' "$devices"

    grep -q 'CUDA0:' <<<"$devices" ||
        die "CUDA device is not visible to llama-server"

    echo
    echo "OFFLINE GPU RUNTIME PASS"
}

enable_gpu() {
    local addon_dir="${1:-}"

    [[ -n "$addon_dir" ]] ||
        die "usage: $0 enable ADDON_DIR"

    addon_dir="$(
        cd "$addon_dir" &&
        pwd
    )"

    verify_addon_compatibility \
        "$addon_dir"

    (
        cd "$addon_dir"
        sha256sum -c SHA256SUMS >/dev/null
    )

    echo "Loading offline NVIDIA image..."

    docker load \
        -i "$addon_dir/images/llama-gpu.tar" \
        >/dev/null

    local gpu_image

    gpu_image="$(
        awk -F= \
            '$1 == "LLAMA_GPU_IMAGE" {print substr($0, index($0, "=") + 1)}' \
            "$addon_dir/versions.gpu.env"
    )"

    docker image inspect \
        "$gpu_image" \
        >/dev/null

    echo "Checking NVIDIA runtime..."

    docker run \
        --rm \
        --gpus all \
        "$gpu_image" \
        --list-devices \
        | grep -q 'CUDA0:' ||
        die "NVIDIA GPU is unavailable to Docker"

    echo "Starting GPU llama-server..."

    gpu_compose \
        "$addon_dir" \
        up \
        -d \
        --pull never \
        --force-recreate \
        --wait \
        llama-server

    gpu_compose \
        "$addon_dir" \
        up \
        -d \
        --pull never \
        --wait

    verify_gpu_runtime \
        "$addon_dir"

    "$ROOT/offline/manage.sh" verify

    echo
    echo "OFFLINE NVIDIA GPU ENABLE PASS"
}

disable_gpu() {
    echo "Restoring CPU llama-server..."

    base_compose \
        up \
        -d \
        --pull never \
        --force-recreate \
        --wait \
        llama-server

    base_compose \
        up \
        -d \
        --pull never \
        --wait

    local cid
    local requests

    cid="$(
        base_compose \
            ps -q llama-server
    )"

    requests="$(
        docker inspect \
            "$cid" \
            --format '{{json .HostConfig.DeviceRequests}}'
    )"

    [[ "$requests" == "null" ]] ||
        die "CPU llama-server still has a GPU device request"

    "$ROOT/offline/manage.sh" verify

    echo
    echo "OFFLINE CPU FALLBACK PASS"
}

status_gpu() {
    local cid

    cid="$(
        base_compose \
            ps -q llama-server
    )"

    [[ -n "$cid" ]] ||
        die "llama-server is not running"

    echo "image=$(
        docker inspect \
            "$cid" \
            --format '{{.Config.Image}}'
    )"

    echo "device_requests=$(
        docker inspect \
            "$cid" \
            --format '{{json .HostConfig.DeviceRequests}}'
    )"
}

case "${1:-}" in
    enable)
        enable_gpu "${2:-}"
        ;;

    disable)
        disable_gpu
        ;;

    status)
        status_gpu
        ;;

    *)
        echo \
            "usage: $0 {enable ADDON_DIR|disable|status}" \
            >&2
        exit 2
        ;;
esac
