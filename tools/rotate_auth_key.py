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
        os.fchmod(descriptor, 0o600)

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
        raise SystemExit("invalid owner id")

    registry_path = Path(
        os.environ.get(
            "CHAT_AUTH_REGISTRY_PATH",
            "runtime/secrets/chat_auth.json",
        )
    )

    key_path = Path(args.key_file)

    # Validate the current registry with production code first.
    AuthRegistry.from_file(
        registry_path
    )

    data = json.loads(
        registry_path.read_text(
            encoding="utf-8"
        )
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

    new_key = secrets.token_urlsafe(32)

    new_digest = hashlib.sha256(
        new_key.encode("utf-8")
    ).hexdigest()

    matching[0]["api_key_sha256"] = (
        new_digest
    )

    write_private(
        registry_path,
        json.dumps(
            data,
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )

    write_private(
        key_path,
        new_key + "\n",
    )

    # Validate final state using the same parser used by the server.
    registry = AuthRegistry.from_file(
        registry_path
    )

    identity = registry.authenticate(
        key_path.read_text(
            encoding="utf-8"
        ).strip()
    )

    if (
        identity is None
        or identity.owner_id != owner
    ):
        raise RuntimeError(
            "rotated credential validation failed"
        )

    print(
        f"AUTH ROTATION PASS owner_id={owner}"
    )
    print(
        f"client_key_file={key_path}"
    )


if __name__ == "__main__":
    main()
