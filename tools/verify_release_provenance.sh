#!/usr/bin/env bash

set -euo pipefail

CPU_BUNDLE="${1:?Usage: verify_release_provenance.sh CPU_BUNDLE [GPU_ADDON]}"
GPU_ADDON="${2:-}"

ROOT="$(
    cd "$(dirname "${BASH_SOURCE[0]}")/.." &&
    pwd
)"

cd "$ROOT"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

manifest_value() {
    local file="$1"
    local key="$2"

    awk -F= \
        -v key="$key" \
        '$1 == key {print substr($0, index($0, "=") + 1)}' \
        "$file"
}

[[ -f "$CPU_BUNDLE/BUNDLE-MANIFEST.txt" ]] ||
    die "CPU bundle manifest is missing"

if ! git diff --quiet --ignore-submodules --; then
    die "working tree has unstaged changes"
fi

if ! git diff --cached --quiet --ignore-submodules --; then
    die "working tree has staged changes"
fi

if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    die "working tree has untracked source files"
fi

SOURCE_SHA="$(git rev-parse HEAD)"

CPU_SHA="$(
    manifest_value \
        "$CPU_BUNDLE/BUNDLE-MANIFEST.txt" \
        source_git_sha
)"

CPU_STATE="$(
    manifest_value \
        "$CPU_BUNDLE/BUNDLE-MANIFEST.txt" \
        source_state
)"

CPU_VERSION="$(
    manifest_value \
        "$CPU_BUNDLE/BUNDLE-MANIFEST.txt" \
        bundle_version
)"

CPU_ARCH="$(
    manifest_value \
        "$CPU_BUNDLE/BUNDLE-MANIFEST.txt" \
        architecture
)"

[[ "$CPU_STATE" == "clean" ]] ||
    die "CPU bundle was not built from a clean tree"

[[ "$CPU_SHA" == "$SOURCE_SHA" ]] ||
    die "CPU bundle source SHA does not match current HEAD"

[[ -n "$CPU_VERSION" ]] ||
    die "CPU bundle version is missing"

[[ -n "$CPU_ARCH" ]] ||
    die "CPU bundle architecture is missing"

echo "PASS CPU bundle source_state=clean"
echo "PASS CPU bundle source_git_sha=$CPU_SHA"
echo "PASS CPU bundle version=$CPU_VERSION"
echo "PASS CPU bundle architecture=$CPU_ARCH"

if [[ -n "$GPU_ADDON" ]]; then
    [[ -f "$GPU_ADDON/GPU-MANIFEST.txt" ]] ||
        die "GPU add-on manifest is missing"

    GPU_SHA="$(
        manifest_value \
            "$GPU_ADDON/GPU-MANIFEST.txt" \
            source_git_sha
    )"

    GPU_STATE="$(
        manifest_value \
            "$GPU_ADDON/GPU-MANIFEST.txt" \
            source_state
    )"

    GPU_VERSION="$(
        manifest_value \
            "$GPU_ADDON/GPU-MANIFEST.txt" \
            bundle_version
    )"

    GPU_ARCH="$(
        manifest_value \
            "$GPU_ADDON/GPU-MANIFEST.txt" \
            architecture
    )"

    [[ "$GPU_STATE" == "clean" ]] ||
        die "GPU add-on was not built from a clean tree"

    [[ "$GPU_SHA" == "$SOURCE_SHA" ]] ||
        die "GPU add-on source SHA does not match current HEAD"

    [[ "$GPU_SHA" == "$CPU_SHA" ]] ||
        die "CPU bundle and GPU add-on source SHAs differ"

    [[ "$GPU_VERSION" == "$CPU_VERSION" ]] ||
        die "CPU bundle and GPU add-on versions differ"

    [[ "$GPU_ARCH" == "$CPU_ARCH" ]] ||
        die "CPU bundle and GPU add-on architectures differ"

    echo "PASS GPU add-on source_state=clean"
    echo "PASS GPU add-on source_git_sha=$GPU_SHA"
    echo "PASS CPU/GPU version compatibility"
    echo "PASS CPU/GPU architecture compatibility"
fi

echo
echo "RELEASE PROVENANCE PASS"
