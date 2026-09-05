#!/usr/bin/env bash

set -euo pipefail

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

cd "$ROOT"

source .env
source versions.env

: "${CHATBOT_IMAGE:?CHATBOT_IMAGE is required}"
: "${LLAMA_CPU_IMAGE:?LLAMA_CPU_IMAGE is required}"
: "${POSTGRES_IMAGE:?POSTGRES_IMAGE is required}"
: "${NGINX_IMAGE:?NGINX_IMAGE is required}"
: "${MODEL_DIR:?MODEL_DIR is required}"
: "${LLAMA_MODEL_NAME:?LLAMA_MODEL_NAME is required}"

GIT_SHA="$(
    git rev-parse HEAD
)"

SHORT_SHA="$(
    git rev-parse --short=12 HEAD
)"

BUNDLE_VERSION="${BUNDLE_VERSION:-$SHORT_SHA}"
DIST_ROOT="${DIST_ROOT:-dist}"

BUNDLE_NAME="chatbot-offline-${BUNDLE_VERSION}"
BUNDLE_DIR="${DIST_ROOT}/${BUNDLE_NAME}"

if [[ -e "$BUNDLE_DIR" ]]; then
    echo "ERROR: bundle already exists: $BUNDLE_DIR" >&2
    exit 1
fi

MODEL_SOURCE="${MODEL_DIR}/${LLAMA_MODEL_NAME}"

if [[ ! -f "$MODEL_SOURCE" ]]; then
    echo "ERROR: model not found: $MODEL_SOURCE" >&2
    exit 1
fi

for image in \
    "$CHATBOT_IMAGE" \
    "$LLAMA_CPU_IMAGE" \
    "$POSTGRES_IMAGE" \
    "$NGINX_IMAGE"
do
    docker image inspect "$image" >/dev/null
done

CHATBOT_TAG="chatbot-offline/chatbot:${BUNDLE_VERSION}"
LLAMA_TAG="chatbot-offline/llama-cpu:${BUNDLE_VERSION}"
POSTGRES_TAG="chatbot-offline/postgres:${BUNDLE_VERSION}"
NGINX_TAG="chatbot-offline/nginx:${BUNDLE_VERSION}"

docker tag "$CHATBOT_IMAGE" "$CHATBOT_TAG"
docker tag "$LLAMA_CPU_IMAGE" "$LLAMA_TAG"
docker tag "$POSTGRES_IMAGE" "$POSTGRES_TAG"
docker tag "$NGINX_IMAGE" "$NGINX_TAG"

mkdir -p \
    "$BUNDLE_DIR/images" \
    "$BUNDLE_DIR/runtime/models"

cp compose.yaml "$BUNDLE_DIR/"
cp .env.example "$BUNDLE_DIR/"
cp -a offline "$BUNDLE_DIR/"
cp versions.env "$BUNDLE_DIR/versions.env"

cp -a nginx "$BUNDLE_DIR/"
cp -a pipelines "$BUNDLE_DIR/"
cp -a database "$BUNDLE_DIR/"

mkdir -p "$BUNDLE_DIR/data"
cp -a data/documents "$BUNDLE_DIR/data/"

cp "$MODEL_SOURCE" \
    "$BUNDLE_DIR/runtime/models/$LLAMA_MODEL_NAME"

# Production bundle keeps chatbot private behind Nginx.
python3 - "$BUNDLE_DIR/compose.yaml" <<'PY_BUNDLE_COMPOSE'
from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text(
    encoding="utf-8"
)

old = (
    '    ports:\n'
    '      - "127.0.0.1:1416:1416"\n'
)

new = (
    '    expose:\n'
    '      - "1416"\n'
)

if old not in text:
    raise SystemExit(
        "chatbot host-port block not found"
    )

text = text.replace(
    old,
    new,
    1,
)

path.write_text(
    text,
    encoding="utf-8",
)

print(
    "PRODUCTION BUNDLE COMPOSE PASS"
)
PY_BUNDLE_COMPOSE

docker save \
    -o "$BUNDLE_DIR/images/chatbot.tar" \
    "$CHATBOT_TAG"

docker save \
    -o "$BUNDLE_DIR/images/llama-cpu.tar" \
    "$LLAMA_TAG"

docker save \
    -o "$BUNDLE_DIR/images/postgres.tar" \
    "$POSTGRES_TAG"

docker save \
    -o "$BUNDLE_DIR/images/nginx.tar" \
    "$NGINX_TAG"

python3 - \
    "$BUNDLE_DIR/versions.env" \
    "$CHATBOT_TAG" \
    "$LLAMA_TAG" \
    "$POSTGRES_TAG" \
    "$NGINX_TAG" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

replacements = {
    "CHATBOT_IMAGE": sys.argv[2],
    "LLAMA_CPU_IMAGE": sys.argv[3],
    "POSTGRES_IMAGE": sys.argv[4],
    "NGINX_IMAGE": sys.argv[5],
}

lines = []

for line in path.read_text(
    encoding="utf-8"
).splitlines():
    key = line.partition("=")[0]

    if key in replacements:
        line = (
            f"{key}="
            f"{replacements[key]}"
        )

    lines.append(line)

path.write_text(
    "\n".join(lines) + "\n",
    encoding="utf-8",
)
PY

cat > "$BUNDLE_DIR/BUNDLE-MANIFEST.txt" <<EOF
bundle_version=${BUNDLE_VERSION}
source_git_sha=${GIT_SHA}
architecture=$(uname -m)

chatbot_image=${CHATBOT_TAG}
llama_cpu_image=${LLAMA_TAG}
postgres_image=${POSTGRES_TAG}
nginx_image=${NGINX_TAG}

llama_model=${LLAMA_MODEL_NAME}
embedding_model=${EMBEDDING_MODEL}
embedding_dimension=${EMBEDDING_DIMENSION}
EOF

(
    cd "$BUNDLE_DIR"

    find . \
        -type f \
        ! -name SHA256SUMS \
        -print0 \
        | sort -z \
        | xargs -0 sha256sum \
        > SHA256SUMS
)

echo
echo "OFFLINE BUNDLE BUILD PASS"
echo "bundle=$BUNDLE_DIR"
echo "version=$BUNDLE_VERSION"
