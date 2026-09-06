"""Docker image helpers."""

from __future__ import annotations

import subprocess
from pathlib import Path


def docker(
    *args: str,
) -> None:
    subprocess.run(
        [
            "docker",
            *args,
        ],
        check=True,
    )


def require_image(
    image: str,
) -> None:
    subprocess.run(
        [
            "docker",
            "image",
            "inspect",
            image,
        ],
        stdout=subprocess.DEVNULL,
        check=True,
    )


def tag(
    source: str,
    target: str,
) -> None:
    docker(
        "tag",
        source,
        target,
    )


def save(
    image: str,
    path: Path,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    docker(
        "save",
        "-o",
        str(path),
        image,
    )
