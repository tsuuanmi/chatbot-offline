#!/usr/bin/env bash

offline_gpu_image() {
    offline_manifest_value \
        "$OFFLINE_ROOT/versions.gpu.env" \
        LLAMA_GPU_IMAGE
}

offline_gpu_profile_for_memory() {
    local memory_mib="$1"

    [[ "$memory_mib" =~ ^[0-9]+$ ]] ||
        return 1

    (( memory_mib >= 6144 )) ||
        return 1

    if (( memory_mib >= 16384 )); then
        printf '%s\n' \
            "full|99|99|$memory_mib"
    else
        printf '%s\n' \
            "conservative|16|0|$memory_mib"
    fi
}

offline_gpu_memory_mib() {
    command -v nvidia-smi \
        >/dev/null 2>&1 ||
        return 1

    local memory_mib

    memory_mib="$(
        nvidia-smi \
            --query-gpu=memory.total \
            --format=csv,noheader,nounits \
            2>/dev/null \
        | awk '
            NR == 1 {
                gsub(/[[:space:]]/, "", $0)

                if ($0 ~ /^[0-9]+$/) {
                    print $0
                }

                exit
            }
        '
    )"

    [[ -n "$memory_mib" ]] ||
        return 1

    printf '%s\n' \
        "$memory_mib"
}

offline_gpu_profile() {
    offline_gpu_available ||
        return 1

    local memory_mib

    memory_mib="$(
        offline_gpu_memory_mib
    )" || return 1

    offline_gpu_profile_for_memory \
        "$memory_mib"
}
offline_gpu_available() {
    local gpu_image

    gpu_image="$(
        offline_gpu_image
    )"

    [[ -n "$gpu_image" ]] ||
        return 1

    [[ -f "$OFFLINE_ROOT/images/llama-gpu.tar" ]] ||
        return 1

    docker image inspect \
        "$gpu_image" \
        >/dev/null 2>&1 ||
        return 1

    docker run \
        --rm \
        --gpus all \
        "$gpu_image" \
        --list-devices \
        2>/dev/null \
    | grep -q 'CUDA0:'
}

offline_gpu_runtime() {
    local container_id

    container_id="$(
        offline_gpu_compose \
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
        offline_gpu_image
    )"

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
    echo "OFFLINE GPU RUNTIME PASS"
}

offline_gpu_enable() {
    [[ -f "$OFFLINE_ROOT/images/llama-gpu.tar" ]] ||
        offline_die \
            "embedded NVIDIA image is missing"

    echo \
        "Loading NVIDIA image..."

    docker load \
        -i "$OFFLINE_ROOT/images/llama-gpu.tar" \
        >/dev/null

    local gpu_image

    gpu_image="$(
        offline_gpu_image
    )"

    docker image inspect \
        "$gpu_image" \
        >/dev/null

    echo \
        "Checking NVIDIA runtime..."

    local profile_output
    local profile
    local main_layers
    local draft_layers
    local memory_mib

    profile_output="$(
        offline_gpu_profile
    )" ||
        offline_die \
            "Supported NVIDIA GPU requires CUDA, nvidia-smi, and at least 6144 MiB VRAM"

    IFS='|' read -r \
        profile \
        main_layers \
        draft_layers \
        memory_mib \
        <<<"$profile_output"

    offline_set_env \
        CHATBOT_GPU_PROFILE \
        "$profile"

    offline_set_env \
        CHATBOT_GPU_MEMORY_MIB \
        "$memory_mib"

    offline_set_env \
        LLAMA_GPU_LAYERS \
        "$main_layers"

    offline_set_env \
        LLAMA_GPU_LAYERS_DRAFT \
        "$draft_layers"

    echo \
        "GPU profile=$profile memory=${memory_mib}MiB layers=${main_layers}/${draft_layers}"

    echo \
        "Starting GPU runtime..."

    offline_gpu_compose \
        up \
        -d \
        --pull never \
        --force-recreate \
        --wait \
        llama-server

    offline_gpu_compose \
        up \
        -d \
        --pull never \
        --wait

    offline_gpu_runtime

    offline_set_env \
        CHATBOT_ACCELERATOR \
        gpu

    offline_verify

    echo
    echo \
        "OFFLINE NVIDIA GPU ENABLE PASS"
}

offline_gpu_disable() {
    echo \
        "Restoring CPU runtime..."

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

    offline_set_env \
        CHATBOT_ACCELERATOR \
        cpu

    offline_set_env \
        CHATBOT_GPU_PROFILE \
        none

    offline_set_env \
        CHATBOT_GPU_MEMORY_MIB \
        0

    offline_set_env \
        LLAMA_GPU_LAYERS \
        0

    offline_set_env \
        LLAMA_GPU_LAYERS_DRAFT \
        0

    offline_verify

    echo
    echo \
        "OFFLINE CPU FALLBACK PASS"
}

offline_gpu_status() {
    local container_id

    container_id="$(
        offline_runtime_compose \
            ps -q llama-server
    )"

    [[ -n "$container_id" ]] ||
        offline_die \
            "llama-server is not running"

    echo \
        "accelerator=$(offline_accelerator)"

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
