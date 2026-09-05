#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="${1:?Usage: verify_offline_bundle.sh BUNDLE_DIR}"

required=(
    compose.yaml
    versions.env
    .env.example
    BUNDLE-MANIFEST.txt
    SHA256SUMS
    nginx/nginx.conf
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

if [[ -f "$BUNDLE_DIR/.env" ]]; then
    echo "ERROR: private .env included in bundle" >&2
    exit 1
fi

(
    cd "$BUNDLE_DIR"
    sha256sum -c SHA256SUMS
)

echo
echo "OFFLINE BUNDLE VERIFY PASS"
