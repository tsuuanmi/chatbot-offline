"""Smoke test PostgreSQL conversation persistence."""

from __future__ import annotations

import json
import urllib.request
from uuid import uuid4


BASE_URL = "http://127.0.0.1:1416"


def chat(
    *,
    message: str,
    conversation_id: str,
) -> dict:
    request = urllib.request.Request(
        f"{BASE_URL}/chat/run",
        data=json.dumps(
            {
                "message": message,
                "conversation_id": conversation_id,
            }
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
        },
    )

    with urllib.request.urlopen(
        request,
        timeout=60,
    ) as response:
        return json.load(response)["result"]


def main() -> None:
    conversation_id = str(
        uuid4()
    )

    first = chat(
        message=(
            "FST cao hay thấp phản ánh mối quan hệ "
            "di truyền như thế nào giữa các quần thể?"
        ),
        conversation_id=conversation_id,
    )

    if first.get("conversation_id") != conversation_id:
        raise SystemExit(
            "FAIL: first conversation_id mismatch"
        )

    if first.get("turn") != 1:
        raise SystemExit(
            f"FAIL: expected turn 1, got {first.get('turn')}"
        )

    second = chat(
        message=(
            "Biểu đồ Venn thể hiện mối quan hệ gì "
            "giữa các vùng dữ liệu trong hệ thống giám định?"
        ),
        conversation_id=conversation_id,
    )

    if second.get("conversation_id") != conversation_id:
        raise SystemExit(
            "FAIL: second conversation_id mismatch"
        )

    if second.get("turn") != 2:
        raise SystemExit(
            f"FAIL: expected turn 2, got {second.get('turn')}"
        )

    print(
        f"conversation_id={conversation_id}"
    )
    print("turn=1 PASS")
    print("turn=2 PASS")
    print("M6A HISTORY SMOKE PASS")


if __name__ == "__main__":
    main()
