#!/usr/bin/env bash

set -euo pipefail

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

cd "$ROOT"

SOURCE_STATE="clean"

if ! git diff --quiet --ignore-submodules --; then
    SOURCE_STATE="dirty"
fi

if ! git diff --cached --quiet --ignore-submodules --; then
    SOURCE_STATE="dirty"
fi

if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    SOURCE_STATE="dirty"
fi

if [[ "$SOURCE_STATE" == "dirty" ]] &&
   [[ "${ALLOW_DIRTY_BUNDLE:-0}" != "1" ]]
then
    echo "ERROR: refusing to build GPU add-on from a dirty working tree" >&2
    echo "Commit changes first, or use ALLOW_DIRTY_BUNDLE=1 for development testing" >&2
    exit 1
fi

source versions.env

: "${LLAMA_GPU_IMAGE:?LLAMA_GPU_IMAGE is required}"

docker image inspect "$LLAMA_GPU_IMAGE" >/dev/null

GIT_SHA="$(git rev-parse HEAD)"
SHORT_SHA="$(git rev-parse --short=12 HEAD)"

BUNDLE_VERSION="${BUNDLE_VERSION:-$SHORT_SHA}"
DIST_ROOT="${DIST_ROOT:-dist}"

ADDON_NAME="chatbot-offline-gpu-nvidia-${BUNDLE_VERSION}"
ADDON_DIR="${DIST_ROOT}/${ADDON_NAME}"

if [[ -e "$ADDON_DIR" ]]; then
    echo "ERROR: GPU add-on already exists: $ADDON_DIR" >&2
    exit 1
fi

LOCAL_GPU_TAG="chatbot-offline/llama-gpu:${BUNDLE_VERSION}"

docker tag \
    "$LLAMA_GPU_IMAGE" \
    "$LOCAL_GPU_TAG"

mkdir -p \
    "$ADDON_DIR/images"

docker save \
    -o "$ADDON_DIR/images/llama-gpu.tar" \
    "$LOCAL_GPU_TAG"

cat > "$ADDON_DIR/versions.gpu.env" <<EOF
LLAMA_GPU_IMAGE=${LOCAL_GPU_TAG}
LLAMA_GPU_LAYERS=99
EOF

cat > "$ADDON_DIR/GPU-MANIFEST.txt" <<EOF
addon_type=nvidia
bundle_version=${BUNDLE_VERSION}
source_git_sha=${GIT_SHA}
source_state=${SOURCE_STATE}
architecture=$(uname -m)
llama_gpu_image=${LOCAL_GPU_TAG}
llama_gpu_source_image=${LLAMA_GPU_IMAGE}
EOF

(
    cd "$ADDON_DIR"

    find . \
        -type f \
        ! -name SHA256SUMS \
        -print0 \
        | sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

echo
echo "OFFLINE GPU ADD-ON BUILD PASS"
echo "addon=$ADDON_DIR"
echo "version=$BUNDLE_VERSION"
