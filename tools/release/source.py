"""Release source-state helpers."""

from __future__ import annotations

import os
import platform
import subprocess
from dataclasses import dataclass


@dataclass(
    frozen=True,
    slots=True,
)
class Source:
    sha: str
    short_sha: str
    state: str
    architecture: str


def git(
    *args: str,
) -> str:
    return subprocess.run(
        [
            "git",
            *args,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
    ).stdout.strip()


def inspect_source() -> Source:
    status = git(
        "status",
        "--porcelain",
        "--untracked-files=normal",
    )

    state = (
        "dirty"
        if status
        else "clean"
    )

    if (
        state == "dirty"
        and os.environ.get(
            "ALLOW_DIRTY_BUNDLE",
            "0",
        )
        != "1"
    ):
        raise RuntimeError(
            "refusing to build release artifact "
            "from a dirty working tree; "
            "commit changes first or use "
            "ALLOW_DIRTY_BUNDLE=1 for development"
        )

    return Source(
        sha=git(
            "rev-parse",
            "HEAD",
        ),
        short_sha=git(
            "rev-parse",
            "--short=12",
            "HEAD",
        ),
        state=state,
        architecture=platform.machine(),
    )
