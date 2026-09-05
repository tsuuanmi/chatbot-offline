"""Benchmark authenticated production SSE chat latency."""

from __future__ import annotations

import argparse
import json
import os
import statistics
import time
import urllib.request

from tools.http_client import json_headers


DEFAULT_PROMPT = (
    "Giải thích khái niệm heterozygosity "
    "trong di truyền quần thể."
)


def one_run(
    url: str,
    prompt: str,
) -> dict[str, float | int]:
    request = urllib.request.Request(
        url,
        data=json.dumps(
            {
                "message": prompt,
            },
            ensure_ascii=False,
        ).encode("utf-8"),
        headers=json_headers(),
        method="POST",
    )

    started = time.perf_counter()

    first_chunk_at: float | None = None
    chunks = 0
    characters = 0
    saw_start = False
    saw_end = False

    with urllib.request.urlopen(
        request,
        timeout=300,
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

            event_type = event.get(
                "type"
            )

            if event_type == "start":
                saw_start = True

            elif event_type == "chunk":
                content = event.get(
                    "content",
                    "",
                )

                if content:
                    if first_chunk_at is None:
                        first_chunk_at = (
                            time.perf_counter()
                        )

                    chunks += 1
                    characters += len(content)

            elif event_type == "end":
                saw_end = True

            elif event_type == "error":
                raise RuntimeError(
                    f"stream error: {event}"
                )

    finished = time.perf_counter()

    if not saw_start:
        raise RuntimeError(
            "missing start event"
        )

    if not saw_end:
        raise RuntimeError(
            "missing end event"
        )

    if first_chunk_at is None:
        raise RuntimeError(
            "stream produced no content"
        )

    ttft = first_chunk_at - started
    total = finished - started

    generation_time = max(
        total - ttft,
        0.000001,
    )

    chars_per_second = (
        characters / generation_time
    )

    return {
        "ttft": ttft,
        "total": total,
        "chunks": chunks,
        "characters": characters,
        "chars_per_second": chars_per_second,
    }


def median(
    results: list[dict[str, float | int]],
    key: str,
) -> float:
    return statistics.median(
        float(result[key])
        for result in results
    )


def mean(
    results: list[dict[str, float | int]],
    key: str,
) -> float:
    return statistics.mean(
        float(result[key])
        for result in results
    )


def main() -> None:
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--label",
        required=True,
    )

    parser.add_argument(
        "--url",
        default=os.environ.get(
            "GATEWAY_URL",
            "http://127.0.0.1:18080",
        ),
    )

    parser.add_argument(
        "--runs",
        type=int,
        default=7,
    )

    parser.add_argument(
        "--warmup",
        type=int,
        default=1,
    )

    parser.add_argument(
        "--pause",
        type=float,
        default=1.0,
    )

    parser.add_argument(
        "--prompt",
        default=DEFAULT_PROMPT,
    )

    args = parser.parse_args()

    url = (
        args.url.rstrip("/")
        + "/chat/stream"
    )

    for number in range(
        1,
        args.warmup + 1,
    ):
        result = one_run(
            url,
            args.prompt,
        )

        print(
            "warmup="
            f"{number} "
            f"ttft={result['ttft']:.3f}s "
            f"total={result['total']:.3f}s "
            f"chunks={result['chunks']}"
        )

        time.sleep(
            args.pause
        )

    results = []

    for number in range(
        1,
        args.runs + 1,
    ):
        result = one_run(
            url,
            args.prompt,
        )

        results.append(
            result
        )

        print(
            f"run={number} "
            f"ttft={result['ttft']:.3f}s "
            f"total={result['total']:.3f}s "
            f"chunks={result['chunks']} "
            f"chars={result['characters']} "
            f"chars_per_second="
            f"{result['chars_per_second']:.1f}"
        )

        time.sleep(
            args.pause
        )

    summary = {
        "label": args.label,
        "runs": args.runs,
        "median_ttft_seconds": median(
            results,
            "ttft",
        ),
        "median_total_seconds": median(
            results,
            "total",
        ),
        "mean_total_seconds": mean(
            results,
            "total",
        ),
        "median_chars_per_second": median(
            results,
            "chars_per_second",
        ),
        "median_chunks": median(
            results,
            "chunks",
        ),
        "median_characters": median(
            results,
            "characters",
        ),
    }

    print()
    print(
        "RESULT "
        + json.dumps(
            summary,
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
