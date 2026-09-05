"""Create and validate local offline authentication secrets."""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import stat
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(
        0,
        str(PROJECT_ROOT),
    )

from chatbot_app.auth import AuthRegistry


DEFAULT_OWNER_ID = "local-development"

REGISTRY_PATH = Path(
    os.environ.get(
        "CHAT_AUTH_REGISTRY_PATH",
        "runtime/secrets/chat_auth.json",
    )
)

CLIENT_KEY_PATH = Path(
    os.environ.get(
        "CHAT_CLIENT_API_KEY_FILE",
        "runtime/secrets/chat_api_key",
    )
)


def _write_exclusive(
    path: Path,
    content: str,
) -> None:
    descriptor = os.open(
        path,
        (
            os.O_WRONLY
            | os.O_CREAT
            | os.O_EXCL
        ),
        0o600,
    )

    try:
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
    except Exception:
        path.unlink(
            missing_ok=True
        )
        raise


def _require_private_file(
    path: Path,
    *,
    label: str,
) -> None:
    if not path.is_file():
        raise RuntimeError(
            f"Missing {label}: {path}"
        )

    if path.is_symlink():
        raise RuntimeError(
            f"{label} must not be a symbolic link"
        )

    mode = stat.S_IMODE(
        path.stat().st_mode
    )

    if mode & 0o077:
        raise RuntimeError(
            f"{label} permissions are too broad: "
            f"{mode:04o}; expected 0600 or stricter"
        )


def check() -> None:
    _require_private_file(
        REGISTRY_PATH,
        label="auth registry",
    )

    _require_private_file(
        CLIENT_KEY_PATH,
        label="client API key",
    )

    registry = AuthRegistry.from_file(
        REGISTRY_PATH
    )

    api_key = CLIENT_KEY_PATH.read_text(
        encoding="utf-8"
    ).strip()

    if not api_key:
        raise RuntimeError(
            "Client API key is empty"
        )

    identity = registry.authenticate(
        api_key
    )

    if identity is None:
        raise RuntimeError(
            "Client API key does not match authentication registry"
        )

    print(
        f"AUTH CONFIG PASS owner_id={identity.owner_id}"
    )


def bootstrap() -> None:
    REGISTRY_PATH.parent.mkdir(
        parents=True,
        exist_ok=True,
        mode=0o700,
    )

    REGISTRY_PATH.parent.chmod(
        0o700
    )

    registry_exists = (
        REGISTRY_PATH.exists()
    )
    key_exists = (
        CLIENT_KEY_PATH.exists()
    )

    if registry_exists or key_exists:
        if not (
            registry_exists
            and key_exists
        ):
            raise RuntimeError(
                "Auth secret state is incomplete; "
                "registry and client key must both exist"
            )

        check()
        print(
            "AUTH SECRETS ALREADY EXIST"
        )
        return

    api_key = secrets.token_urlsafe(
        32
    )

    digest = hashlib.sha256(
        api_key.encode("utf-8")
    ).hexdigest()

    registry = {
        "version": 1,
        "identities": [
            {
                "owner_id": DEFAULT_OWNER_ID,
                "api_key_sha256": digest,
            }
        ],
    }

    created: list[Path] = []

    try:
        _write_exclusive(
            REGISTRY_PATH,
            json.dumps(
                registry,
                indent=2,
                sort_keys=True,
            )
            + "\n",
        )
        created.append(
            REGISTRY_PATH
        )

        _write_exclusive(
            CLIENT_KEY_PATH,
            api_key + "\n",
        )
        created.append(
            CLIENT_KEY_PATH
        )
    except Exception:
        for path in created:
            path.unlink(
                missing_ok=True
            )
        raise

    check()

    print(
        "AUTH SECRETS CREATED"
    )
    print(
        f"registry={REGISTRY_PATH}"
    )
    print(
        f"client_key_file={CLIENT_KEY_PATH}"
    )


def main() -> None:
    if sys.argv[1:] == [
        "--check"
    ]:
        check()
        return

    if sys.argv[1:]:
        raise SystemExit(
            "usage: bootstrap_auth.py [--check]"
        )

    bootstrap()


if __name__ == "__main__":
    main()
