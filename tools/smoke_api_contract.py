"""Smoke test stable authenticated chat API behavior."""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from http_client import (
    json_headers,
)


BASE_URL = "http://127.0.0.1:1416"


def request_chat(
    payload: dict[str, object],
    *,
    authenticated: bool = True,
    invalid_key: bool = False,
) -> tuple[int, dict[str, object]]:
    headers = {
        "Content-Type": "application/json",
    }

    if authenticated:
        if invalid_key:
            headers["Authorization"] = (
                "Bearer "
                + ("invalid-" * 8)
            )
        else:
            headers.update(
                json_headers()
            )

    request = urllib.request.Request(
        f"{BASE_URL}/chat/run",
        data=json.dumps(
            payload
        ).encode("utf-8"),
        headers=headers,
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=60,
        ) as response:
            return (
                response.status,
                json.load(response),
            )
    except urllib.error.HTTPError as error:
        raw = error.read().decode(
            "utf-8",
            errors="replace",
        )

        try:
            body = json.loads(
                raw
            )
        except json.JSONDecodeError:
            body = {
                "detail": raw,
            }

        return (
            error.code,
            body,
        )


def main() -> None:
    status, _ = request_chat(
        {
            "message": "STR là gì?",
        },
        authenticated=False,
    )

    if status != 401:
        raise SystemExit(
            "FAIL missing auth: "
            f"expected 401, got {status}"
        )

    print(
        "PASS missing auth -> 401"
    )

    status, _ = request_chat(
        {
            "message": "STR là gì?",
        },
        invalid_key=True,
    )

    if status != 401:
        raise SystemExit(
            "FAIL invalid auth: "
            f"expected 401, got {status}"
        )

    print(
        "PASS invalid auth -> 401"
    )

    status, _ = request_chat(
        {
            "message": "STR là gì?",
            "conversation_id": "not-a-uuid",
        }
    )

    if status != 422:
        raise SystemExit(
            "FAIL invalid conversation_id: "
            f"expected 422, got {status}"
        )

    print(
        "PASS invalid conversation_id -> 422"
    )

    status, body = request_chat(
        {
            "message": (
                "FST cao hay thấp phản ánh "
                "mối quan hệ di truyền như thế nào "
                "giữa các quần thể?"
            )
        }
    )

    if status != 200:
        raise SystemExit(
            f"FAIL stateless request: HTTP {status}"
        )

    result = body.get(
        "result"
    )

    if not isinstance(
        result,
        dict,
    ):
        raise SystemExit(
            "FAIL stateless response has no result"
        )

    if (
        "conversation_id" in result
        or "turn" in result
    ):
        raise SystemExit(
            "FAIL stateless request unexpectedly persisted"
        )

    print(
        "PASS authenticated stateless request"
    )
    print()
    print(
        "API CONTRACT SMOKE PASS"
    )


if __name__ == "__main__":
    main()
