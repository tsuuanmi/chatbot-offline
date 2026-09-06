"""CPU offline bundle builder."""

from __future__ import annotations

import os
import shutil
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


def copy_tree(
    source: Path,
    target: Path,
) -> None:
    shutil.copytree(
        source,
        target,
    )


def rewrite_versions(
    path: Path,
    images: dict[str, str],
) -> None:
    lines = []

    for line in path.read_text(
        encoding="utf-8"
    ).splitlines():
        key = line.partition(
            "="
        )[0]

        if key in images:
            line = (
                f"{key}="
                f"{images[key]}"
            )

        lines.append(
            line
        )

    path.write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )


def privatize_chatbot(
    path: Path,
) -> None:
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
        raise RuntimeError(
            "chatbot host-port block "
            "not found in compose.yaml"
        )

    path.write_text(
        text.replace(
            old,
            new,
            1,
        ),
        encoding="utf-8",
    )


def build(
    version: str | None = None,
    dist: Path = Path("dist"),
) -> Path:
    source = inspect_source()

    values = read_env(
        Path(".env"),
        Path("versions.env"),
    )

    require(
        values,
        "CHATBOT_IMAGE",
        "LLAMA_CPU_IMAGE",
        "POSTGRES_IMAGE",
        "NGINX_IMAGE",
        "MODEL_DIR",
        "LLAMA_MODEL_NAME",
        "MTP_MODEL_NAME",
        "EMBEDDING_MODEL",
        "EMBEDDING_DIMENSION",
    )

    version = (
        version
        or os.environ.get(
            "BUNDLE_VERSION"
        )
        or source.short_sha
    )

    bundle = (
        dist
        / f"chatbot-offline-{version}"
    )

    if bundle.exists():
        raise RuntimeError(
            f"bundle already exists: {bundle}"
        )

    model_dir = Path(
        values["MODEL_DIR"]
    )

    model = (
        model_dir
        / values["LLAMA_MODEL_NAME"]
    )

    mtp_model = (
        model_dir
        / values["MTP_MODEL_NAME"]
    )

    for label, path in (
        ("model", model),
        ("MTP model", mtp_model),
    ):
        if not path.is_file():
            raise RuntimeError(
                f"{label} not found: {path}"
            )

    source_images = {
        "CHATBOT_IMAGE": (
            values["CHATBOT_IMAGE"]
        ),
        "LLAMA_CPU_IMAGE": (
            values["LLAMA_CPU_IMAGE"]
        ),
        "POSTGRES_IMAGE": (
            values["POSTGRES_IMAGE"]
        ),
        "NGINX_IMAGE": (
            values["NGINX_IMAGE"]
        ),
    }

    local_images = {
        "CHATBOT_IMAGE": (
            f"chatbot-offline/chatbot:"
            f"{version}"
        ),
        "LLAMA_CPU_IMAGE": (
            f"chatbot-offline/llama-cpu:"
            f"{version}"
        ),
        "POSTGRES_IMAGE": (
            f"chatbot-offline/postgres:"
            f"{version}"
        ),
        "NGINX_IMAGE": (
            f"chatbot-offline/nginx:"
            f"{version}"
        ),
    }

    for image in source_images.values():
        require_image(
            image
        )

    for key, source_image in (
        source_images.items()
    ):
        tag(
            source_image,
            local_images[key],
        )

    (
        bundle
        / "runtime/models"
    ).mkdir(
        parents=True
    )

    shutil.copy2(
        "compose.yaml",
        bundle / "compose.yaml",
    )

    shutil.copy2(
        "compose.gpu.yaml",
        bundle / "compose.gpu.yaml",
    )

    shutil.copy2(
        ".env.example",
        bundle / ".env.example",
    )

    shutil.copy2(
        "versions.env",
        bundle / "versions.env",
    )

    copy_tree(
        Path("offline"),
        bundle / "offline",
    )

    copy_tree(
        Path("nginx"),
        bundle / "nginx",
    )

    copy_tree(
        Path("pipelines"),
        bundle / "pipelines",
    )

    copy_tree(
        Path("database"),
        bundle / "database",
    )

    (
        bundle
        / "data"
    ).mkdir()

    copy_tree(
        Path("data/documents"),
        bundle / "data/documents",
    )

    shutil.copy2(
        model,
        (
            bundle
            / "runtime/models"
            / values[
                "LLAMA_MODEL_NAME"
            ]
        ),
    )

    shutil.copy2(
        mtp_model,
        (
            bundle
            / "runtime/models"
            / values[
                "MTP_MODEL_NAME"
            ]
        ),
    )

    privatize_chatbot(
        bundle
        / "compose.yaml"
    )

    rewrite_versions(
        bundle
        / "versions.env",
        local_images,
    )

    images = (
        bundle
        / "images"
    )

    save(
        local_images[
            "CHATBOT_IMAGE"
        ],
        images / "chatbot.tar",
    )

    save(
        local_images[
            "LLAMA_CPU_IMAGE"
        ],
        images / "llama-cpu.tar",
    )

    save(
        local_images[
            "POSTGRES_IMAGE"
        ],
        images / "postgres.tar",
    )

    save(
        local_images[
            "NGINX_IMAGE"
        ],
        images / "nginx.tar",
    )

    write_manifest(
        bundle
        / "BUNDLE-MANIFEST.txt",
        {
            "bundle_version": version,
            "source_git_sha": (
                source.sha
            ),
            "source_state": (
                source.state
            ),
            "architecture": (
                source.architecture
            ),
            "chatbot_image": (
                local_images[
                    "CHATBOT_IMAGE"
                ]
            ),
            "llama_cpu_image": (
                local_images[
                    "LLAMA_CPU_IMAGE"
                ]
            ),
            "postgres_image": (
                local_images[
                    "POSTGRES_IMAGE"
                ]
            ),
            "nginx_image": (
                local_images[
                    "NGINX_IMAGE"
                ]
            ),
            "llama_model": (
                values[
                    "LLAMA_MODEL_NAME"
                ]
            ),
            "mtp_model": (
                values[
                    "MTP_MODEL_NAME"
                ]
            ),
            "llama_spec_type": (
                values.get(
                    "LLAMA_SPEC_TYPE",
                    "draft-mtp",
                )
            ),
            "llama_spec_draft_n_max": (
                values.get(
                    "LLAMA_SPEC_DRAFT_N_MAX",
                    "2",
                )
            ),
            "embedding_model": (
                values[
                    "EMBEDDING_MODEL"
                ]
            ),
            "embedding_dimension": (
                values[
                    "EMBEDDING_DIMENSION"
                ]
            ),
        },
    )

    write_checksums(
        bundle
    )

    print()
    print(
        "OFFLINE CPU BUNDLE BUILD PASS"
    )
    print(
        f"bundle={bundle}"
    )

    return bundle
