"""NVIDIA offline add-on builder."""

from __future__ import annotations

import os
from pathlib import Path

from .env import (
    read_env,
    require,
)
from .image import (
    require_image,
    save,
    tag,
)
from .manifest import (
    write_checksums,
    write_manifest,
)
from .source import inspect_source


def build(
    version: str | None = None,
    dist: Path = Path("dist"),
) -> Path:
    source = inspect_source()

    values = read_env(
        Path("versions.env")
    )

    require(
        values,
        "LLAMA_GPU_IMAGE",
    )

    version = (
        version
        or os.environ.get(
            "BUNDLE_VERSION"
        )
        or source.short_sha
    )

    addon = (
        dist
        / (
            "chatbot-offline-"
            f"gpu-nvidia-{version}"
        )
    )

    if addon.exists():
        raise RuntimeError(
            f"GPU add-on already exists: "
            f"{addon}"
        )

    source_image = (
        values[
            "LLAMA_GPU_IMAGE"
        ]
    )

    require_image(
        source_image
    )

    local_image = (
        "chatbot-offline/"
        f"llama-gpu:{version}"
    )

    tag(
        source_image,
        local_image,
    )

    (
        addon
        / "images"
    ).mkdir(
        parents=True
    )

    save(
        local_image,
        addon
        / "images/llama-gpu.tar",
    )

    (
        addon
        / "versions.gpu.env"
    ).write_text(
        (
            f"LLAMA_GPU_IMAGE="
            f"{local_image}\n"
            "LLAMA_GPU_LAYERS=99\n"
            "LLAMA_GPU_LAYERS_DRAFT=99\n"
        ),
        encoding="utf-8",
    )

    write_manifest(
        addon
        / "GPU-MANIFEST.txt",
        {
            "addon_type": "nvidia",
            "bundle_version": (
                version
            ),
            "source_git_sha": (
                source.sha
            ),
            "source_state": (
                source.state
            ),
            "architecture": (
                source.architecture
            ),
            "llama_gpu_image": (
                local_image
            ),
            "llama_gpu_source_image": (
                source_image
            ),
        },
    )

    write_checksums(
        addon
    )

    print()
    print(
        "OFFLINE GPU ADD-ON BUILD PASS"
    )
    print(
        f"addon={addon}"
    )

    return addon
