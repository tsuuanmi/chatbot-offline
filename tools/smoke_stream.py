"""Smoke test for authenticated SSE chat streaming."""

from __future__ import annotations

import json
import urllib.request

from tools.http_client import json_headers


URL = "http://127.0.0.1:1416/chat/stream"


request = urllib.request.Request(
    URL,
    data=json.dumps(
        {
            "message": (
                "Giải thích khái niệm heterozygosity "
                "trong di truyền quần thể."
            )
        }
    ).encode("utf-8"),
    headers=json_headers(),
    method="POST",
)


events = []

with urllib.request.urlopen(
    request,
    timeout=120,
) as response:
    if response.status != 200:
        raise RuntimeError(
            f"unexpected status {response.status}"
        )

    content_type = response.headers.get(
        "Content-Type",
        "",
    )

    if not content_type.startswith(
        "text/event-stream"
    ):
        raise RuntimeError(
            f"unexpected content type {content_type}"
        )

    for raw in response:
        line = raw.decode(
            "utf-8"
        ).strip()

        if not line.startswith(
            "data:"
        ):
            continue

        event = json.loads(
            line[5:].strip()
        )

        events.append(event)


types = [
    event.get("type")
    for event in events
]

if not types or types[0] != "start":
    raise RuntimeError(
        f"missing start event: {types}"
    )

chunks = [
    event.get("content", "")
    for event in events
    if event.get("type") == "chunk"
]

if not "".join(chunks).strip():
    raise RuntimeError(
        "stream produced no answer content"
    )

if "end" not in types:
    raise RuntimeError(
        f"missing end event: {types}"
    )

if "error" in types:
    raise RuntimeError(
        f"stream returned error: {events}"
    )

print(
    f"PASS SSE stream -> {len(chunks)} chunks"
)
print("M6C STREAM SMOKE PASS")
