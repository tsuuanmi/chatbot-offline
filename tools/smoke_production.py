"""Production gateway boundary acceptance."""

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


def call(
    path: str,
    *,
    method: str = "GET",
    body: dict[str, object] | None = None,
    authenticated: bool = False,
) -> tuple[int, object]:
    headers: dict[str, str] = {}

    if body is not None:
        headers["Content-Type"] = "application/json"

    if authenticated:
        headers.update(
            json_headers()
        )

    data = (
        json.dumps(body).encode("utf-8")
        if body is not None
        else None
    )

    request = urllib.request.Request(
        BASE_URL + path,
        data=data,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=120,
        ) as response:
            response.read()

            return (
                response.status,
                response.headers,
            )

    except urllib.error.HTTPError as error:
        error.read()

        return (
            error.code,
            error.headers,
        )


def expect(
    label: str,
    actual: int,
    expected: int,
) -> None:
    if actual != expected:
        raise RuntimeError(
            f"{label}: expected={expected} "
            f"actual={actual}"
        )

    print(
        f"PASS {label} -> {actual}"
    )


def main() -> None:
    status, headers = call(
        "/live"
    )

    expect(
        "gateway liveness",
        status,
        200,
    )

    expected_headers = {
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
    }

    for name, expected in expected_headers.items():
        actual = headers.get(name)

        if actual != expected:
            raise RuntimeError(
                f"security header {name}: "
                f"expected={expected!r} "
                f"actual={actual!r}"
            )

    print(
        "PASS gateway security headers"
    )

    status, _ = call(
        "/healthcheck/run",
        method="POST",
        body={},
    )

    expect(
        "gateway readiness",
        status,
        200,
    )

    # Hayhooks discovery/status remains maintenance-only.
    status, _ = call(
        "/status"
    )

    expect(
        "internal status blocked",
        status,
        404,
    )

    status, _ = call(
        "/classify/run",
        method="POST",
        body={
            "message": "test",
        },
        authenticated=True,
    )

    expect(
        "internal pipeline blocked",
        status,
        404,
    )

    oversized = "x" * 70000

    status, _ = call(
        "/chat/run",
        method="POST",
        authenticated=True,
        body={
            "message": oversized,
        },
    )

    expect(
        "oversized request blocked",
        status,
        413,
    )

    print()
    print(
        "M7 PRODUCTION GATEWAY PASS"
    )


if __name__ == "__main__":
    main()
