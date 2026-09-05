"""Explicit citation IDs and post-generation citation validation."""

from __future__ import annotations

import re
from typing import Mapping


_CITATION_PATTERN = re.compile(
    r"\[cite:([A-Za-z0-9][A-Za-z0-9._:-]{0,127})\]"
)


def citation_id_from_meta(
    meta: Mapping[str, object],
    *,
    fallback_id: str,
) -> str:
    source_id = str(meta.get("source_id") or "").strip()
    number = str(meta.get("no") or "").strip()

    if source_id and number:
        raw = f"{source_id}:{number}"
    else:
        raw = fallback_id[:24]

    return re.sub(
        r"[^A-Za-z0-9._:-]+",
        "-",
        raw,
    ).strip("-")


def citation_token(citation_id: str) -> str:
    return f"[cite:{citation_id}]"


def citation_ids(text: str) -> set[str]:
    return set(_CITATION_PATTERN.findall(text))


def sanitize_citations(
    text: str,
    allowed: set[str],
) -> str:
    """Remove only unknown explicit citations.

    Ordinary brackets such as [1] or [DNA] are untouched.
    """

    return _CITATION_PATTERN.sub(
        lambda match: (
            match.group(0)
            if match.group(1) in allowed
            else ""
        ),
        text,
    )
