"""Offline artifact verification."""

from __future__ import annotations

import platform
from pathlib import Path

from .manifest import (
    read_manifest,
    verify_checksums,
)


CPU_REQUIRED = (
    "compose.yaml",
    "compose.gpu.yaml",
    "versions.env",
    ".env.example",
    "BUNDLE-MANIFEST.txt",
    "SHA256SUMS",
    "nginx/nginx.conf",
    "offline/install.sh",
    "offline/manage.sh",
    "offline/lib/common.sh",
    "offline/lib/check.py",
    "offline/lib/gpu.sh",
    "offline/lib/accept.sh",
    "pipelines",
    "database",
    "data/documents",
    "runtime/models",
    "images/chatbot.tar",
    "images/llama-cpu.tar",
    "images/postgres.tar",
    "images/nginx.tar",
)

GPU_REQUIRED = (
    "GPU-MANIFEST.txt",
    "versions.gpu.env",
    "SHA256SUMS",
    "images/llama-gpu.tar",
)


def require_paths(
    root: Path,
    paths: tuple[str, ...],
) -> None:
    for relative in paths:
        if not (
            root
            / relative
        ).exists():
            raise RuntimeError(
                f"required artifact path "
                f"is missing: {relative}"
            )


def reject_private_state(
    root: Path,
) -> None:
    if (
        root / ".env"
    ).exists():
        raise RuntimeError(
            "private .env is included "
            "in release artifact"
        )

    for path in root.rglob("*"):
        parts = path.parts

        if (
            "runtime" in parts
            and "secrets" in parts
        ):
            raise RuntimeError(
                "runtime secret path is "
                f"included: {path}"
            )


def verify_network_boundary(
    compose: Path,
) -> None:
    lines = compose.read_text(
        encoding="utf-8"
    ).splitlines()

    inside = False
    block: list[str] = []

    for line in lines:
        if line == "  chatbot:":
            inside = True
            block.append(
                line
            )
            continue

        if inside:
            if (
                line.startswith(
                    "  "
                )
                and not line.startswith(
                    "    "
                )
                and line.endswith(
                    ":"
                )
            ):
                break

            block.append(
                line
            )

    if not block:
        raise RuntimeError(
            "chatbot service missing "
            "from production compose"
        )

    if "    ports:" in block:
        raise RuntimeError(
            "production chatbot "
            "publishes host ports"
        )

    if "    expose:" not in block:
        raise RuntimeError(
            "production chatbot "
            "internal expose is missing"
        )

    print(
        "PASS production chatbot "
        "network boundary"
    )


def verify_cpu(
    root: Path,
) -> dict[str, str]:
    require_paths(
        root,
        CPU_REQUIRED,
    )

    reject_private_state(
        root
    )

    if (
        root
        / "images/llama-gpu.tar"
    ).exists():
        raise RuntimeError(
            "GPU image must not be "
            "included in CPU bundle"
        )

    verify_network_boundary(
        root / "compose.yaml"
    )

    verify_checksums(
        root
    )

    manifest = read_manifest(
        root
        / "BUNDLE-MANIFEST.txt"
    )

    if manifest.get(
        "architecture"
    ) != platform.machine():
        raise RuntimeError(
            "CPU bundle architecture "
            "does not match host"
        )

    print()
    print(
        "OFFLINE CPU BUNDLE VERIFY PASS"
    )

    return manifest


def verify_gpu(
    root: Path,
) -> dict[str, str]:
    require_paths(
        root,
        GPU_REQUIRED,
    )

    reject_private_state(
        root
    )

    manifest = read_manifest(
        root
        / "GPU-MANIFEST.txt"
    )

    if manifest.get(
        "addon_type"
    ) != "nvidia":
        raise RuntimeError(
            "unsupported GPU add-on type: "
            f"{manifest.get('addon_type')}"
        )

    if manifest.get(
        "architecture"
    ) != platform.machine():
        raise RuntimeError(
            "GPU add-on architecture "
            "does not match host"
        )

    verify_checksums(
        root
    )

    print()
    print(
        "OFFLINE GPU ADD-ON VERIFY PASS"
    )

    return manifest


def verify_pair(
    cpu: Path,
    gpu: Path,
) -> None:
    cpu_manifest = verify_cpu(
        cpu
    )

    gpu_manifest = verify_gpu(
        gpu
    )

    for key in (
        "bundle_version",
        "source_git_sha",
        "architecture",
    ):
        if (
            cpu_manifest.get(
                key
            )
            != gpu_manifest.get(
                key
            )
        ):
            raise RuntimeError(
                f"CPU/GPU provenance "
                f"mismatch: {key}"
            )

    if (
        cpu_manifest.get(
            "source_state"
        )
        != "clean"
        or gpu_manifest.get(
            "source_state"
        )
        != "clean"
    ):
        raise RuntimeError(
            "release pair was not built "
            "from clean source state"
        )

    print()
    print(
        "CPU/GPU RELEASE PAIR PASS"
    )
