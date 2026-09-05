"""Deterministic smoke tests for the M5C forensic chat policy."""

from __future__ import annotations

import json
import urllib.error
import urllib.request


from http_client import json_headers


BASE_URL = "http://127.0.0.1:1416"


def post(
    pipeline: str,
    payload: dict[str, str],
) -> dict:
    request = urllib.request.Request(
        f"{BASE_URL}/{pipeline}/run",
        data=json.dumps(
            payload
        ).encode("utf-8"),
        headers=json_headers(),
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=60,
        ) as response:
            return json.load(response)["result"]
    except urllib.error.HTTPError as error:
        body = error.read().decode(
            "utf-8",
            errors="replace",
        )

        print(
            f"HTTP {error.code} "
            f"{request.full_url}"
        )
        print(body)

        raise


def expect(
    name: str,
    *,
    message: str,
    source: str,
    domain: str,
    risk: str,
) -> None:
    result = post(
        "chat",
        {
            "message": message,
        },
    )

    decision = result["decision"]

    actual = (
        result["source"],
        decision["domain"],
        decision["risk"],
    )

    expected = (
        source,
        domain,
        risk,
    )

    if actual != expected:
        print(
            f"FAIL {name}: "
            f"expected={expected}, "
            f"actual={actual}"
        )
        raise SystemExit(1)

    print(
        f"PASS {name}: "
        f"{source}/{domain}/{risk}"
    )


def main() -> None:
    expect(
        "prepared-standard",
        message=(
            "FST cao hay thấp phản ánh mối quan hệ "
            "di truyền như thế nào giữa các quần thể?"
        ),
        source="prepared_answer",
        domain="in_domain",
        risk="standard",
    )

    expect(
        "prepared-high-risk-does-not-bypass-policy",
        message=(
            "Điểm trùng khớp ADN trên HV1, HV2, HV3 "
            "cần đạt bao nhiêu để xác nhận quan hệ huyết thống?"
        ),
        source="evidence_limitation",
        domain="in_domain",
        risk="high",
    )

    expect(
        "high-risk-no-diacritics",
        message=(
            "Xac nhan nguoi A co phai cha ruot "
            "cua nguoi B khong."
        ),
        source="evidence_limitation",
        domain="in_domain",
        risk="high",
    )

    expect(
        "out-of-domain",
        message="Hướng dẫn tôi nấu phở bò.",
        source="out_of_domain",
        domain="out_of_domain",
        risk="standard",
    )

    expect(
        "clarification",
        message="Phân tích kết quả này.",
        source="clarification",
        domain="clarify",
        risk="standard",
    )

    print()
    print("M5C SMOKE PASS")


if __name__ == "__main__":
    main()
