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

offline_gpu_residual_limit_mib() {
    local total_mib="$1"

    [[ "$total_mib" =~ ^[0-9]+$ ]] ||
        return 1

    (( total_mib >= 6144 )) ||
        return 1

    local limit_mib=$((total_mib - 6144))

    if (( limit_mib < 1024 )); then
        limit_mib=1024
    fi

    printf '%s\n' \
        "$limit_mib"
}

offline_gpu_residual_memory_allowed() {
    local total_mib="$1"
    local used_mib="$2"

    [[ "$used_mib" =~ ^[0-9]+$ ]] ||
        return 1

    local limit_mib

    limit_mib="$(offline_gpu_residual_limit_mib "$total_mib")" ||
        return 1

    (( used_mib < limit_mib ))
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


offline_gpu_residual_limit_for_memory() {
    local memory_mib="$1"

    [[ "$memory_mib" =~ ^[0-9]+$ ]] ||
        return 1

    (( memory_mib >= 6144 )) ||
        return 1

    local limit_mib=$((memory_mib - 6144))

    if (( limit_mib < 1024 )); then
        limit_mib=1024
    fi

    printf '%s\n' \
        "$limit_mib"
}

offline_gpu_residual_within_limit() {
    local memory_mib="$1"
    local used_mib="$2"

    [[ "$used_mib" =~ ^[0-9]+$ ]] ||
        return 1

    local limit_mib

    limit_mib="$(
        offline_gpu_residual_limit_for_memory \
            "$memory_mib"
    )" || return 1

    (( used_mib < limit_mib ))
}

offline_gpu_existing_chatbot_memory_mib() {
    local container_pid

    container_pid="$(
        docker inspect \
            --format '{{.State.Pid}}' \
            chatbot-llama \
            2>/dev/null \
        || true
    )"

    if ! [[ "$container_pid" =~ ^[1-9][0-9]*$ ]]; then
        printf '0\n'
        return 0
    fi

    local processes

    processes="$(
        nvidia-smi \
            --query-compute-apps=pid,used_memory \
            --format=csv,noheader,nounits \
            2>/dev/null
    )" || return 1

    awk \
        -F, \
        -v target="$container_pid" '
            {
                gsub(/[[:space:]]/, "", $1)
                gsub(/[[:space:]]/, "", $2)

                if (
                    $1 == target &&
                    $2 ~ /^[0-9]+$/
                ) {
                    total += $2
                }
            }

            END {
                print total + 0
            }
        ' \
        <<<"$processes"
}

offline_gpu_residual_preflight() {
    local expected_total_mib="${1:-}"

    [[ "$expected_total_mib" =~ ^[0-9]+$ ]] || {
        echo "Invalid expected GPU memory: $expected_total_mib" >&2
        return 1
    }

    command -v nvidia-smi >/dev/null 2>&1 || {
        echo "nvidia-smi is unavailable" >&2
        return 1
    }

    local measurement

    measurement="$(nvidia-smi \
        --query-gpu=memory.total,memory.used \
        --format=csv,noheader,nounits \
        2>/dev/null | head -n 1)" || {
        echo "Unable to measure NVIDIA GPU memory" >&2
        return 1
    }

    [[ -n "$measurement" ]] || {
        echo "NVIDIA returned no GPU memory measurement" >&2
        return 1
    }

    local total_mib
    local used_mib
    local extra

    IFS=, read -r \
        total_mib \
        used_mib \
        extra \
        <<<"$measurement"

    total_mib="${total_mib//[[:space:]]/}"
    used_mib="${used_mib//[[:space:]]/}"
    extra="${extra//[[:space:]]/}"

    if [[ -n "$extra" ]] ||
       [[ ! "$total_mib" =~ ^[0-9]+$ ]] ||
       [[ ! "$used_mib" =~ ^[0-9]+$ ]]
    then
        echo "Invalid NVIDIA GPU memory measurement: $measurement" >&2
        return 1
    fi

    if (( total_mib != expected_total_mib )); then
        echo \
            "GPU memory changed during detection: expected=${expected_total_mib}MiB actual=${total_mib}MiB" \
            >&2
        return 1
    fi

    local limit_mib

    limit_mib="$(offline_gpu_residual_limit_mib "$total_mib")" ||
        return 1

    echo \
        "GPU residual memory: ${used_mib} MiB of ${total_mib} MiB (limit ${limit_mib} MiB)" \
        >&2

    if ! offline_gpu_residual_within_limit \
        "$total_mib" \
        "$used_mib"
    then
        local processes

        processes="$(nvidia-smi \
            --query-compute-apps=pid,process_name,used_memory \
            --format=csv,noheader,nounits \
            2>/dev/null || true)"

        if [[ -n "$processes" ]]; then
            echo "GPU compute processes currently using memory:" >&2
            printf "%s
" "$processes" >&2
        fi

        echo \
            "GPU does not have enough free memory for the selected Chatbot profile" \
            >&2

        return 1
    fi

    return 0
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

offline_gpu_existing_runtime_active() {
    docker inspect \
        chatbot-llama \
        >/dev/null 2>&1 ||
        return 1

    local running
    local requests

    running="$(docker inspect \
        --format '{{.State.Running}}' \
        chatbot-llama \
        2>/dev/null
    )"

    [[ "$running" == "true" ]] ||
        return 1

    requests="$(docker inspect \
        --format '{{json .HostConfig.DeviceRequests}}' \
        chatbot-llama \
        2>/dev/null
    )"

    [[ -n "$requests" ]] ||
        return 1

    [[ "$requests" != "null" ]] ||
        return 1

    [[ "$requests" != "[]" ]]
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

    echo \
        "Checking host GPU memory headroom..."

    offline_gpu_preflight_host_memory ||
        offline_die \
            "Insufficient free GPU memory; stop substantial GPU processes and retry"

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

offline_gpu_memory_usage_mib() {
    command -v nvidia-smi \
        >/dev/null 2>&1 ||
        return 1

    local measurement

    measurement="$(
        nvidia-smi \
            --query-gpu=memory.total,memory.used \
            --format=csv,noheader,nounits \
            2>/dev/null |
        awk -F, '
            NR == 1 {
                gsub(/[[:space:]]/, "", $1)
                gsub(/[[:space:]]/, "", $2)

                if (
                    $1 ~ /^[0-9]+$/ &&
                    $2 ~ /^[0-9]+$/
                ) {
                    print $1 "|" $2
                }

                exit
            }
        '
    )"

    [[ -n "$measurement" ]] ||
        return 1

    printf '%s\n' \
        "$measurement"
}

offline_gpu_existing_runtime_uses_gpu() {
    docker inspect \
        chatbot-llama \
        >/dev/null 2>&1 ||
        return 1

    local running

    running="$(
        docker inspect \
            --format '{{.State.Running}}' \
            chatbot-llama \
            2>/dev/null
    )" || return 1

    [[ "$running" == "true" ]] ||
        return 1

    local requests

    requests="$(
        docker inspect \
            --format \
            '{{json .HostConfig.DeviceRequests}}' \
            chatbot-llama \
            2>/dev/null
    )" || return 1

    [[ "$requests" != "null" ]] &&
        [[ "$requests" != "[]" ]]
}

offline_gpu_preflight_host_memory() {
    if offline_gpu_existing_runtime_uses_gpu; then
        echo \
            "Existing chatbot GPU runtime detected; skipping residual VRAM preflight during in-place upgrade"
        return 0
    fi

    local measurement
    local total_mib
    local used_mib
    local limit_mib

    measurement="$(
        offline_gpu_memory_usage_mib
    )" ||
        return 1

    IFS='|' read -r \
        total_mib \
        used_mib \
        <<<"$measurement"

    limit_mib="$(
        offline_gpu_residual_limit_mib \
            "$total_mib"
    )" ||
        return 1

    echo \
        "GPU residual memory: ${used_mib} MiB of ${total_mib} MiB (limit ${limit_mib} MiB)"

    if ! offline_gpu_residual_memory_allowed \
        "$total_mib" \
        "$used_mib"
    then
        echo \
            "GPU does not have enough free memory for the selected Chatbot profile" >&2

        nvidia-smi \
            --query-compute-apps=pid,process_name,used_memory \
            --format=csv,noheader \
            2>/dev/null \
            >&2 ||
            true

        return 1
    fi

    return 0
}
