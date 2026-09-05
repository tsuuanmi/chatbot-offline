"""Rotate one offline API key without exposing it."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import tempfile
from pathlib import Path

from chatbot_app.auth import AuthRegistry


OWNER_PATTERN = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
)


def write_private(
    path: Path,
    content: str,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
        mode=0o700,
    )

    descriptor, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.",
        dir=path.parent,
    )

    temporary_path = Path(temporary)

    try:
        os.fchmod(
            descriptor,
            0o600,
        )

        with os.fdopen(
            descriptor,
            "w",
            encoding="utf-8",
        ) as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(
            temporary_path,
            path,
        )
    finally:
        temporary_path.unlink(
            missing_ok=True
        )


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--owner",
        required=True,
    )

    parser.add_argument(
        "--key-file",
        required=True,
    )

    args = parser.parse_args()

    owner = args.owner.strip()

    if not OWNER_PATTERN.fullmatch(owner):
        raise SystemExit(
            "invalid owner id"
        )

    registry_path = Path(
        os.environ.get(
            "CHAT_AUTH_REGISTRY_PATH",
            "runtime/secrets/chat_auth.json",
        )
    )

    key_path = Path(
        args.key_file
    )

    registry = AuthRegistry.from_file(
        registry_path
    )

    if not key_path.is_file():
        raise RuntimeError(
            "client key file does not exist"
        )

    current_key = key_path.read_text(
        encoding="utf-8"
    ).strip()

    current_identity = registry.authenticate(
        current_key
    )

    if (
        current_identity is None
        or current_identity.owner_id != owner
    ):
        raise RuntimeError(
            "client key file does not belong to requested owner"
        )

    original_registry = registry_path.read_text(
        encoding="utf-8"
    )

    original_key = (
        current_key + "\n"
    )

    data = json.loads(
        original_registry
    )

    identities = data["identities"]

    matching = [
        item
        for item in identities
        if item["owner_id"] == owner
    ]

    if len(matching) != 1:
        raise RuntimeError(
            "owner must exist exactly once"
        )

    new_key = secrets.token_urlsafe(
        32
    )

    matching[0]["api_key_sha256"] = (
        hashlib.sha256(
            new_key.encode("utf-8")
        ).hexdigest()
    )

    new_registry = (
        json.dumps(
            data,
            indent=2,
            sort_keys=True,
        )
        + "\n"
    )

    try:
        write_private(
            key_path,
            new_key + "\n",
        )

        write_private(
            registry_path,
            new_registry,
        )

        final_registry = AuthRegistry.from_file(
            registry_path
        )

        identity = final_registry.authenticate(
            new_key
        )

        if (
            identity is None
            or identity.owner_id != owner
        ):
            raise RuntimeError(
                "rotated credential validation failed"
            )

    except Exception as error:
        rollback_errors = []

        try:
            write_private(
                registry_path,
                original_registry,
            )
        except Exception as rollback_error:
            rollback_errors.append(
                f"registry: {rollback_error}"
            )

        try:
            write_private(
                key_path,
                original_key,
            )
        except Exception as rollback_error:
            rollback_errors.append(
                f"key: {rollback_error}"
            )

        if rollback_errors:
            raise RuntimeError(
                "credential rotation failed and rollback "
                "was incomplete: "
                + "; ".join(rollback_errors)
            ) from error

        raise

    print(
        f"AUTH ROTATION PASS owner_id={owner}"
    )
    print(
        f"client_key_file={key_path}"
    )


if __name__ == "__main__":
    main()
