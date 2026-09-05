"""Production gateway boundary smoke test."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from tools.http_client import json_headers


BASE_URL = os.environ.get(
    "CHAT_GATEWAY_BASE_URL",
    "http://127.0.0.1:18080",
).rstrip("/")


def request(
    path: str,
    *,
    method: str = "GET",
    body: dict[str, object] | None = None,
    authenticated: bool = False,
) -> tuple[int, object]:
    headers = {}

    if body is not None:
        headers["Content-Type"] = (
            "application/json"
        )

    if authenticated:
        headers.update(
            json_headers()
        )

    data = (
        json.dumps(body).encode("utf-8")
        if body is not None
        else None
    )

    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(
            req,
            timeout=120,
        ) as response:
            raw = response.read()
            return response.status, raw
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def expect(
    label: str,
    actual: int,
    expected: int,
) -> None:
    if actual != expected:
        raise RuntimeError(
            f"{label}: expected {expected}, "
            f"got {actual}"
        )

    print(
        f"PASS {label} -> {actual}"
    )


def main() -> None:
    status, _ = request(
        "/live"
    )

    expect(
        "gateway liveness",
        status,
        200,
    )

    status, _ = request(
        "/healthcheck/run",
        method="POST",
        body={},
    )

    expect(
        "gateway readiness",
        status,
        200,
    )

    status, _ = request(
        "/chat/run",
        method="POST",
        body={
            "message": "Hướng dẫn tôi nấu phở."
        },
    )

    expect(
        "gateway chat requires auth",
        status,
        401,
    )

    status, _ = request(
        "/chat/run",
        method="POST",
        authenticated=True,
        body={
            "message": "Hướng dẫn tôi nấu phở."
        },
    )

    expect(
        "authenticated gateway chat",
        status,
        200,
    )

    status, _ = request(
        "/classify/run",
        method="POST",
        authenticated=True,
        body={
            "message": "test"
        },
    )

    expect(
        "internal classify blocked",
        status,
        404,
    )

    status, _ = request(
        "/deploy-yaml",
        method="POST",
        authenticated=True,
        body={},
    )

    expect(
        "runtime management blocked",
        status,
        404,
    )

    print()
    print(
        "M7 GATEWAY SMOKE PASS"
    )


if __name__ == "__main__":
    main()
