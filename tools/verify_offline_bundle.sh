#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="${1:?Usage: verify_offline_bundle.sh BUNDLE_DIR}"

required=(
    compose.yaml
    compose.gpu.yaml
    versions.env
    .env.example
    BUNDLE-MANIFEST.txt
    SHA256SUMS
    nginx/nginx.conf
    offline/install.sh
    offline/manage.sh
    offline/accept.sh
    offline/gpu.sh
    pipelines
    database
    data/documents
    runtime/models
    images/chatbot.tar
    images/llama-cpu.tar
    images/postgres.tar
    images/nginx.tar
)

for path in "${required[@]}"; do
    if [[ ! -e "$BUNDLE_DIR/$path" ]]; then
        echo "ERROR: missing bundle path: $path" >&2
        exit 1
    fi
done

if find "$BUNDLE_DIR" \
    -path '*/runtime/secrets/*' \
    -print \
    -quit \
    | grep -q .
then
    echo "ERROR: runtime secret included in bundle" >&2
    exit 1
fi

if [[ -e "$BUNDLE_DIR/images/llama-gpu.tar" ]]; then
    echo "ERROR: optional GPU image must not be included in CPU bundle" >&2
    exit 1
fi

if [[ -f "$BUNDLE_DIR/.env" ]]; then
    echo "ERROR: private .env included in bundle" >&2
    exit 1
fi

python3 - "$BUNDLE_DIR/compose.yaml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text(
    encoding="utf-8"
).splitlines()

inside = False
block = []

for line in lines:
    if line == "  chatbot:":
        inside = True
        block.append(line)
        continue

    if inside:
        if (
            line.startswith("  ")
            and not line.startswith("    ")
            and line.endswith(":")
        ):
            break

        block.append(line)

if not block:
    raise SystemExit(
        "ERROR: chatbot service missing from production compose"
    )

if any(
    line == "    ports:"
    for line in block
):
    raise SystemExit(
        "ERROR: production chatbot publishes host ports"
    )

if not any(
    line == "    expose:"
    for line in block
):
    raise SystemExit(
        "ERROR: production chatbot internal expose is missing"
    )

print(
    "PASS production chatbot network boundary"
)
PY

(
    cd "$BUNDLE_DIR"
    sha256sum -c SHA256SUMS
)

echo
echo "OFFLINE BUNDLE VERIFY PASS"
