"""Verify runtime secrets are not tracked or logged."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


SECRET_FILES = (
    Path("runtime/secrets/chat_api_key"),
    Path("runtime/secrets/chat_api_key_owner_b"),
    Path("runtime/secrets/llama_api_key"),
    Path("runtime/secrets/postgres_password"),
)


def run(
    *args: str,
) -> str:
    return subprocess.run(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=True,
    ).stdout


def main() -> None:
    tracked = run(
        "git",
        "ls-files",
        "runtime/secrets",
    ).strip()

    if tracked:
        raise RuntimeError(
            "runtime secret files are tracked by git"
        )

    secrets = []

    for path in SECRET_FILES:
        if not path.is_file():
            continue

        value = path.read_text(
            encoding="utf-8"
        ).strip()

        if value:
            secrets.append(value)

    registry_path = Path(
        "runtime/secrets/chat_auth.json"
    )

    if registry_path.is_file():
        registry = json.loads(
            registry_path.read_text(
                encoding="utf-8"
            )
        )

        for identity in registry.get(
            "identities",
            [],
        ):
            if not isinstance(
                identity,
                dict,
            ):
                continue

            digest = identity.get(
                "api_key_sha256"
            )

            if isinstance(
                digest,
                str,
            ) and digest:
                secrets.append(
                    digest
                )

    logs = run(
        "docker",
        "compose",
        "--env-file",
        ".env",
        "--env-file",
        "versions.env",
        "logs",
        "--no-color",
        "chatbot",
        "proxy",
    )

    for value in secrets:
        if value in logs:
            raise RuntimeError(
                "raw secret detected in runtime logs"
            )

    print(
        "PASS runtime secrets are not tracked"
    )
    print(
        "PASS raw secrets are absent from chatbot/proxy logs"
    )
    print()
    print(
        "M7 SECRET AUDIT PASS"
    )


if __name__ == "__main__":
    main()
