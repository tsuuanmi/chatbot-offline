"""Smoke test stable chat API boundary behavior."""

from __future__ import annotations

import json
import urllib.error
import urllib.request


BASE_URL = "http://127.0.0.1:1416"


def request_chat(
    payload: dict[str, object],
) -> tuple[int, dict[str, object]]:
    request = urllib.request.Request(
        f"{BASE_URL}/chat/run",
        data=json.dumps(
            payload
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=60,
        ) as response:
            body = json.load(response)
            return response.status, body
    except urllib.error.HTTPError as error:
        raw = error.read().decode(
            "utf-8",
            errors="replace",
        )

        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {
                "detail": raw,
            }

        return error.code, body


def main() -> None:
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

    result = body.get("result")

    if not isinstance(result, dict):
        raise SystemExit(
            "FAIL stateless response has no result"
        )

    if "conversation_id" in result:
        raise SystemExit(
            "FAIL stateless response unexpectedly persisted"
        )

    if "turn" in result:
        raise SystemExit(
            "FAIL stateless response unexpectedly has turn"
        )

    print(
        "PASS omitted conversation_id remains stateless"
    )

    print()
    print(
        "API CONTRACT SMOKE PASS"
    )


if __name__ == "__main__":
    main()
