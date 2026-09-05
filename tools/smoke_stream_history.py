"""Verify short-lived multi-turn context through SSE streaming."""

from __future__ import annotations

import json
import urllib.request
from uuid import uuid4

from tools.http_client import json_headers


URL = "http://127.0.0.1:1416/chat/stream"


def stream(
    message: str,
    conversation_id: str,
) -> tuple[str, dict[str, object]]:
    request = urllib.request.Request(
        URL,
        data=json.dumps(
            {
                "message": message,
                "conversation_id": conversation_id,
            }
        ).encode("utf-8"),
        headers=json_headers(),
        method="POST",
    )

    chunks: list[str] = []
    end: dict[str, object] | None = None

    with urllib.request.urlopen(
        request,
        timeout=180,
    ) as response:
        if response.status != 200:
            raise RuntimeError(
                f"unexpected status {response.status}"
            )

        for raw in response:
            line = raw.decode(
                "utf-8"
            ).strip()

            if not line.startswith("data:"):
                continue

            event = json.loads(
                line[5:].strip()
            )

            event_type = event.get("type")

            if event_type == "error":
                raise RuntimeError(
                    f"stream error: {event}"
                )

            if event_type == "chunk":
                chunks.append(
                    str(
                        event.get(
                            "content",
                            "",
                        )
                    )
                )

            if event_type == "end":
                end = event

    answer = "".join(chunks)

    if not answer.strip():
        raise RuntimeError(
            "stream returned no answer content"
        )

    if end is None:
        raise RuntimeError(
            "stream returned no end event"
        )

    return answer, end


def main() -> None:
    conversation_id = str(
        uuid4()
    )

    _, first = stream(
        (
            "FST cao hay thấp phản ánh mối quan hệ "
            "di truyền như thế nào giữa các quần thể?"
        ),
        conversation_id,
    )

    if first.get("turn") != 1:
        raise RuntimeError(
            f"expected turn 1, got {first.get('turn')}"
        )

    print(
        "PASS streamed session turn 1"
    )

    _, second = stream(
        "Giải thích rõ hơn ý vừa rồi.",
        conversation_id,
    )

    if second.get("turn") != 2:
        raise RuntimeError(
            f"expected turn 2, got {second.get('turn')}"
        )

    loaded = second.get(
        "history_turns_loaded"
    )

    if (
        not isinstance(loaded, int)
        or loaded < 1
    ):
        raise RuntimeError(
            "streamed follow-up did not load "
            "previous session context"
        )

    decision = second.get(
        "decision"
    )

    if not isinstance(
        decision,
        dict,
    ):
        raise RuntimeError(
            "missing decision metadata"
        )

    if decision.get("domain") != "in_domain":
        raise RuntimeError(
            f"context follow-up unresolved: {decision}"
        )

    reason = str(
        decision.get("reason") or ""
    )

    if not reason.startswith(
        "contextual_"
    ):
        raise RuntimeError(
            f"expected contextual decision: {decision}"
        )

    print(
        "PASS streamed session turn 2 uses context"
    )

    print()
    print(
        "M6C STREAM HISTORY PASS"
    )


if __name__ == "__main__":
    main()
