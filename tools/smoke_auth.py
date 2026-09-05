"""Acceptance tests for global HTTP authentication."""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from http_client import (
    json_headers,
)


BASE_URL = "http://127.0.0.1:1416"


def request(
    path: str,
    *,
    method: str = "GET",
    payload: dict[str, object] | None = None,
    authenticated: bool = False,
) -> int:
    headers: dict[str, str] = {}

    if payload is not None:
        headers[
            "Content-Type"
        ] = "application/json"

    if authenticated:
        headers.update(
            json_headers()
        )

    data = (
        json.dumps(
            payload
        ).encode("utf-8")
        if payload is not None
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
            timeout=60,
        ) as response:
            response.read()
            return response.status
    except urllib.error.HTTPError as error:
        error.read()
        return error.code


def expect(
    name: str,
    actual: int,
    expected: int,
) -> None:
    if actual != expected:
        raise RuntimeError(
            f"{name}: expected HTTP "
            f"{expected}, got {actual}"
        )

    print(
        f"PASS {name} -> {actual}"
    )


def main() -> None:
    expect(
        "public status",
        request(
            "/status"
        ),
        200,
    )

    expect(
        "public readiness",
        request(
            "/healthcheck/run",
            method="POST",
            payload={},
        ),
        200,
    )

    expect(
        "chat requires auth",
        request(
            "/chat/run",
            method="POST",
            payload={
                "message": "STR là gì?",
            },
        ),
        401,
    )

    expect(
        "authenticated chat",
        request(
            "/chat/run",
            method="POST",
            payload={
                "message": (
                    "Hướng dẫn tôi nấu phở bò."
                ),
            },
            authenticated=True,
        ),
        200,
    )

    expect(
        "runtime yaml deploy blocked",
        request(
            "/deploy-yaml",
            method="POST",
            payload={},
            authenticated=True,
        ),
        404,
    )

    expect(
        "runtime files deploy blocked",
        request(
            "/deploy_files",
            method="POST",
            payload={},
            authenticated=True,
        ),
        404,
    )

    expect(
        "runtime undeploy blocked",
        request(
            "/undeploy/chat",
            method="POST",
            authenticated=True,
        ),
        404,
    )

    print()
    print(
        "M6B AUTH SMOKE PASS"
    )


if __name__ == "__main__":
    main()
