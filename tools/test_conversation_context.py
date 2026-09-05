"""Pure tests for bounded conversation context."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from uuid import uuid4

from chatbot_app.conversation import (
    ConversationLockRegistry,
    HistoryContextBuilder,
)


@dataclass
class Turn:
    query: str
    answer: str
    domain: str
    risk: str


def test_history() -> None:
    builder = HistoryContextBuilder(
        max_turns=6,
        max_chars=8000,
    )

    turns = [
        Turn(
            query="FST là gì?",
            answer=(
                "Nội dung [cite:old:1] "
                "giữ [1] và [DNA]."
            ),
            domain="in_domain",
            risk="standard",
        )
    ]

    messages = builder.prompt_messages(
        turns
    )

    assistant = [
        item.content
        for item in messages
        if item.role == "assistant"
    ][0]

    assert "[cite:old:1]" not in assistant
    assert "[1]" in assistant
    assert "[DNA]" in assistant

    contextual = builder.contextual_query(
        "Giải thích rõ hơn.",
        turns,
    )

    assert contextual is not None
    assert "FST là gì?" in contextual

    high_risk = [
        Turn(
            query="Xác nhận cha ruột.",
            answer="Không thể kết luận.",
            domain="in_domain",
            risk="high",
        )
    ]

    assert (
        builder.contextual_query(
            "Giải thích thêm.",
            high_risk,
        )
        is None
    )


async def test_locks() -> None:
    registry = ConversationLockRegistry()

    conversation_id = uuid4()

    assert registry.active_entries == 0

    async with registry.hold(
        conversation_id
    ):
        assert (
            registry.active_entries
            == 1
        )

    assert registry.active_entries == 0


def main() -> None:
    test_history()
    asyncio.run(
        test_locks()
    )

    print(
        "CONVERSATION CONTEXT TEST PASS"
    )


if __name__ == "__main__":
    main()
