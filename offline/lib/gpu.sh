#!/usr/bin/env bash

offline_gpu_compatibility() {
    local addon_dir="$1"

    [[ -f "$OFFLINE_ROOT/BUNDLE-MANIFEST.txt" ]] ||
        offline_die \
            "Base bundle manifest is missing"

    [[ -f "$addon_dir/GPU-MANIFEST.txt" ]] ||
        offline_die \
            "GPU add-on manifest is missing"

    local key
    local base_value
    local addon_value

    for key in \
        source_git_sha \
        architecture \
        bundle_version
    do
        base_value="$(
            offline_manifest_value \
                "$OFFLINE_ROOT/BUNDLE-MANIFEST.txt" \
                "$key"
        )"

        addon_value="$(
            offline_manifest_value \
                "$addon_dir/GPU-MANIFEST.txt" \
                "$key"
        )"

        [[ "$base_value" == "$addon_value" ]] ||
            offline_die \
                "GPU add-on mismatch: $key"
    done
}

offline_gpu_runtime() {
    local addon_dir="$1"

    local container_id

    container_id="$(
        offline_gpu_compose \
            "$addon_dir" \
            ps -q llama-server
    )"

    [[ -n "$container_id" ]] ||
        offline_die \
            "llama-server is not running"

    local requests

    requests="$(
        docker inspect \
            --format \
            '{{json .HostConfig.DeviceRequests}}' \
            "$container_id"
    )"

    [[ "$requests" != "null" ]] ||
        offline_die \
            "llama-server has no GPU device request"

    local expected_image

    expected_image="$(
        offline_manifest_value \
            "$addon_dir/versions.gpu.env" \
            LLAMA_GPU_IMAGE
    )"

    [[ -n "$expected_image" ]] ||
        offline_die \
            "LLAMA_GPU_IMAGE is missing"

    local running_id
    local expected_id

    running_id="$(
        docker inspect \
            --format '{{.Image}}' \
            "$container_id"
    )"

    expected_id="$(
        docker image inspect \
            "$expected_image" \
            --format '{{.Id}}'
    )"

    [[ "$running_id" == "$expected_id" ]] ||
        offline_die \
            "llama-server is not using the GPU image"

    local devices

    devices="$(
        docker exec \
            "$container_id" \
            /app/llama-server \
            --list-devices
    )"

    printf '%s\n' \
        "$devices"

    grep -q 'CUDA0:' \
        <<<"$devices" ||
        offline_die \
            "CUDA device is not visible to llama-server"

    echo
    echo \
        "OFFLINE GPU RUNTIME PASS"
}

offline_gpu_enable() {
    local addon="${1:-}"

    [[ -n "$addon" ]] ||
        offline_die \
            "usage: manage.sh gpu enable ADDON_DIR"

    local addon_dir

    addon_dir="$(
        readlink -f "$addon"
    )"

    [[ -d "$addon_dir" ]] ||
        offline_die \
            "GPU add-on directory does not exist"

    offline_gpu_compatibility \
        "$addon_dir"

    offline_checksum \
        "$addon_dir"

    echo \
        "Loading offline NVIDIA image..."

    docker load \
        -i "$addon_dir/images/llama-gpu.tar" \
        >/dev/null

    local gpu_image

    gpu_image="$(
        offline_manifest_value \
            "$addon_dir/versions.gpu.env" \
            LLAMA_GPU_IMAGE
    )"

    docker image inspect \
        "$gpu_image" \
        >/dev/null

    echo \
        "Checking NVIDIA runtime..."

    docker run \
        --rm \
        --gpus all \
        "$gpu_image" \
        --list-devices \
        | grep -q 'CUDA0:' ||
        offline_die \
            "NVIDIA GPU is unavailable to Docker"

    echo \
        "Starting GPU llama-server..."

    offline_gpu_compose \
        "$addon_dir" \
        up \
        -d \
        --pull never \
        --force-recreate \
        --wait \
        llama-server

    offline_gpu_compose \
        "$addon_dir" \
        up \
        -d \
        --pull never \
        --wait

    offline_gpu_runtime \
        "$addon_dir"

    offline_verify

    echo
    echo \
        "OFFLINE NVIDIA GPU ENABLE PASS"
}

offline_gpu_disable() {
    echo \
        "Restoring CPU llama-server..."

    offline_compose \
        up \
        -d \
        --pull never \
        --force-recreate \
        --wait \
        llama-server

    offline_compose \
        up \
        -d \
        --pull never \
        --wait

    local container_id

    container_id="$(
        offline_compose \
            ps -q llama-server
    )"

    local requests

    requests="$(
        docker inspect \
            --format \
            '{{json .HostConfig.DeviceRequests}}' \
            "$container_id"
    )"

    [[ "$requests" == "null" ]] ||
        offline_die \
            "CPU llama-server still has a GPU device request"

    offline_verify

    echo
    echo \
        "OFFLINE CPU FALLBACK PASS"
}

offline_gpu_status() {
    local container_id

    container_id="$(
        offline_compose \
            ps -q llama-server
    )"

    [[ -n "$container_id" ]] ||
        offline_die \
            "llama-server is not running"

    echo "image=$(
        docker inspect \
            "$container_id" \
            --format '{{.Config.Image}}'
    )"

    echo "device_requests=$(
        docker inspect \
            "$container_id" \
            --format \
            '{{json .HostConfig.DeviceRequests}}'
    )"
}
