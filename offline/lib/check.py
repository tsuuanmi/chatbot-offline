"""Offline deployment checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path


def digest(
    path: Path,
) -> str:
    hasher = hashlib.sha256()

    with path.open("rb") as handle:
        while chunk := handle.read(
            1024 * 1024
        ):
            hasher.update(chunk)

    return hasher.hexdigest()


def checksum(
    root: Path,
) -> None:
    checksum_file = (
        root / "SHA256SUMS"
    )

    if not checksum_file.is_file():
        raise RuntimeError(
            "SHA256SUMS is missing"
        )

    for raw in checksum_file.read_text(
        encoding="utf-8"
    ).splitlines():
        if not raw.strip():
            continue

        expected, separator, name = (
            raw.partition("  ")
        )

        if not separator:
            raise RuntimeError(
                f"invalid checksum line: {raw!r}"
            )

        path = root / name

        if not path.is_file():
            raise RuntimeError(
                f"missing checksummed file: {name}"
            )

        if digest(path) != expected:
            raise RuntimeError(
                f"checksum mismatch: {name}"
            )

    print(
        "OFFLINE CHECKSUM PASS"
    )


def runtime(
    gateway: str,
    key_file: Path,
) -> None:
    gateway = gateway.rstrip("/")

    if not key_file.is_file():
        raise RuntimeError(
            "client API key is missing"
        )

    api_key = key_file.read_text(
        encoding="utf-8"
    ).strip()

    if not api_key:
        raise RuntimeError(
            "client API key is empty"
        )

    with urllib.request.urlopen(
        gateway + "/live",
        timeout=10,
    ) as response:
        if response.status != 200:
            raise RuntimeError(
                "liveness check failed"
            )

    request = urllib.request.Request(
        gateway + "/healthcheck/run",
        data=b"{}",
        headers={
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(
        request,
        timeout=30,
    ) as response:
        body = json.load(response)

    result = body.get("result")

    if (
        not isinstance(result, dict)
        or result.get("status") != "ready"
    ):
        raise RuntimeError(
            f"service is not ready: {result}"
        )

    request = urllib.request.Request(
        gateway + "/chat/run",
        data=json.dumps(
            {
                "message": (
                    "Hướng dẫn tôi nấu phở."
                )
            },
            ensure_ascii=False,
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": (
                "Bearer " + api_key
            ),
        },
        method="POST",
    )

    with urllib.request.urlopen(
        request,
        timeout=120,
    ) as response:
        body = json.load(response)

    if not isinstance(
        body.get("result"),
        dict,
    ):
        raise RuntimeError(
            "invalid authenticated chat response"
        )

    print(
        "OFFLINE VERIFY PASS"
    )


def main() -> None:
    parser = argparse.ArgumentParser()

    commands = parser.add_subparsers(
        dest="command",
        required=True,
    )

    checksum_parser = commands.add_parser(
        "checksum"
    )

    checksum_parser.add_argument(
        "root",
        type=Path,
    )

    runtime_parser = commands.add_parser(
        "runtime"
    )

    runtime_parser.add_argument(
        "gateway"
    )

    runtime_parser.add_argument(
        "key_file",
        type=Path,
    )

    args = parser.parse_args()

    if args.command == "checksum":
        checksum(
            args.root
        )
        return

    runtime(
        args.gateway,
        args.key_file,
    )


if __name__ == "__main__":
    main()
