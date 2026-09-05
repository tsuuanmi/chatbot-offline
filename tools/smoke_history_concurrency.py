"""Verify PostgreSQL conversation turn allocation under concurrency."""

from __future__ import annotations

import asyncio
from uuid import UUID, uuid4

import psycopg

from chatbot_app.database import (
    postgres_connection_string,
)
from chatbot_app.history import (
    get_conversation_repository,
)


OWNER_ID = "concurrency-smoke"


async def cleanup(
    conversation_id: UUID,
) -> None:
    connection = await psycopg.AsyncConnection.connect(
        postgres_connection_string()
    )

    try:
        async with connection.transaction():
            await connection.execute(
                """
                DELETE FROM conversations
                WHERE id = %s
                """,
                (conversation_id,),
            )
    finally:
        await connection.close()


async def main_async() -> None:
    repository = get_conversation_repository()
    conversation_id = uuid4()

    try:
        results = await asyncio.gather(
            repository.append_turn(
                conversation_id,
                owner_id=OWNER_ID,
                query="Concurrent query A",
                answer="Concurrent answer A",
                domain="in_domain",
                risk="standard",
                source="concurrency_smoke",
            ),
            repository.append_turn(
                conversation_id,
                owner_id=OWNER_ID,
                query="Concurrent query B",
                answer="Concurrent answer B",
                domain="in_domain",
                risk="standard",
                source="concurrency_smoke",
            ),
        )

        allocated = sorted(
            item.turn
            for item in results
        )

        if allocated != [1, 2]:
            raise RuntimeError(
                "Concurrent allocation failed: "
                f"{allocated}"
            )

        persisted = await repository.get_turns(
            conversation_id,
            owner_id=OWNER_ID,
            limit=10,
        )

        persisted_turns = [
            item.turn
            for item in persisted
        ]

        if persisted_turns != [1, 2]:
            raise RuntimeError(
                "Unexpected persisted turn order: "
                f"{persisted_turns}"
            )

        print(
            "PASS concurrent allocation -> turns 1,2"
        )
        print(
            "PASS unique persisted turn ordering"
        )
        print()
        print(
            "DB CONCURRENCY SMOKE PASS"
        )
    finally:
        await cleanup(
            conversation_id
        )


def main() -> None:
    asyncio.run(
        main_async()
    )


if __name__ == "__main__":
    main()
