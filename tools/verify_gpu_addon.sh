#!/usr/bin/env bash

set -euo pipefail

ADDON_DIR="${1:?Usage: verify_gpu_addon.sh ADDON_DIR}"

required=(
    GPU-MANIFEST.txt
    versions.gpu.env
    SHA256SUMS
    images/llama-gpu.tar
)

for path in "${required[@]}"; do
    if [[ ! -f "$ADDON_DIR/$path" ]]; then
        echo "ERROR: missing GPU add-on file: $path" >&2
        exit 1
    fi
done

if [[ -f "$ADDON_DIR/.env" ]]; then
    echo "ERROR: private .env included in GPU add-on" >&2
    exit 1
fi

if find "$ADDON_DIR" \
    -path '*/runtime/secrets/*' \
    -print \
    -quit \
    | grep -q .
then
    echo "ERROR: runtime secret included in GPU add-on" >&2
    exit 1
fi

ADDON_TYPE="$(
    awk -F= \
        '$1 == "addon_type" {print $2}' \
        "$ADDON_DIR/GPU-MANIFEST.txt"
)"

[[ "$ADDON_TYPE" == "nvidia" ]] || {
    echo "ERROR: unsupported GPU add-on type: $ADDON_TYPE" >&2
    exit 1
}

ARCH="$(
    awk -F= \
        '$1 == "architecture" {print $2}' \
        "$ADDON_DIR/GPU-MANIFEST.txt"
)"

[[ "$ARCH" == "$(uname -m)" ]] || {
    echo "ERROR: GPU add-on architecture mismatch" >&2
    exit 1
}

(
    cd "$ADDON_DIR"
    sha256sum -c SHA256SUMS
)

echo
echo "OFFLINE GPU ADD-ON VERIFY PASS"
