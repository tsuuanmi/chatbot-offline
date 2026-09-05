"""Verify secret-consuming Compose services receive the secret group."""

from __future__ import annotations

import subprocess


SERVICES = (
    "postgres",
    "db-migrate",
    "index-knowledge",
    "llama-server",
    "chatbot",
)


def main() -> None:
    for service in SERVICES:
        result = subprocess.run(
            [
                "docker",
                "compose",
                "--env-file",
                ".env",
                "--env-file",
                "versions.env",
                "config",
                service,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=True,
        )

        output = result.stdout

        if "group_add:" not in output:
            raise RuntimeError(
                f"{service} is missing group_add"
            )

        print(
            f"PASS secret group {service}"
        )

    print()
    print(
        "SECRET GROUP CONFIG PASS"
    )


if __name__ == "__main__":
    main()
