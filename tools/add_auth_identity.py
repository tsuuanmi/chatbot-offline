"""Add an identity to the local offline authentication registry."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import tempfile
from pathlib import Path


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

    temporary_path = Path(
        temporary
    )

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
            handle.write(
                content
            )
            handle.flush()
            os.fsync(
                handle.fileno()
            )

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

    if not OWNER_PATTERN.fullmatch(
        owner
    ):
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

    registry = json.loads(
        registry_path.read_text(
            encoding="utf-8"
        )
    )

    identities = registry.get(
        "identities"
    )

    if not isinstance(
        identities,
        list,
    ):
        raise RuntimeError(
            "invalid authentication registry"
        )

    existing = [
        item
        for item in identities
        if (
            isinstance(item, dict)
            and item.get("owner_id")
            == owner
        )
    ]

    if existing:
        if len(existing) != 1:
            raise RuntimeError(
                "duplicate owner identity"
            )

        if not key_path.is_file():
            raise RuntimeError(
                "identity already exists but its "
                "client key file is unavailable"
            )

        api_key = key_path.read_text(
            encoding="utf-8"
        ).strip()

        digest = hashlib.sha256(
            api_key.encode("utf-8")
        ).hexdigest()

        if (
            existing[0].get(
                "api_key_sha256"
            )
            != digest
        ):
            raise RuntimeError(
                "existing key does not match registry"
            )

        print(
            f"AUTH IDENTITY PASS owner_id={owner}"
        )
        return

    if key_path.exists():
        raise RuntimeError(
            "key file already exists for an "
            "unregistered identity"
        )

    api_key = secrets.token_urlsafe(
        32
    )

    digest = hashlib.sha256(
        api_key.encode("utf-8")
    ).hexdigest()

    identities.append(
        {
            "owner_id": owner,
            "api_key_sha256": digest,
        }
    )

    write_private(
        registry_path,
        json.dumps(
            registry,
            indent=2,
            sort_keys=True,
        )
        + "\n",
    )

    write_private(
        key_path,
        api_key + "\n",
    )

    print(
        f"AUTH IDENTITY CREATED owner_id={owner}"
    )
    print(
        f"client_key_file={key_path}"
    )


if __name__ == "__main__":
    main()
