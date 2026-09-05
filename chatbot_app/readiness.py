"""Production dependency readiness checks."""

from __future__ import annotations

import asyncio
import os
import urllib.request
from functools import lru_cache

from chatbot_app.history import (
    get_conversation_repository,
)


class ReadinessService:
    """Verify dependencies required for normal chat operation."""

    def __init__(self) -> None:
        self.history = get_conversation_repository()

        base_url = os.environ[
            "LLAMA_BASE_URL"
        ].rstrip("/")

        if base_url.endswith("/v1"):
            base_url = base_url[:-3]

        self.llama_health_url = (
            f"{base_url}/health"
        )

    async def check(
        self,
    ) -> dict[str, str]:
        await self.history.healthcheck()

        await asyncio.to_thread(
            self._check_llama
        )

        return {
            "status": "ready",
            "database": "ok",
            "knowledge": "ok",
            "llama": "ok",
        }

    def _check_llama(self) -> None:
        request = urllib.request.Request(
            self.llama_health_url,
            method="GET",
        )

        with urllib.request.urlopen(
            request,
            timeout=3,
        ) as response:
            if response.status != 200:
                raise RuntimeError(
                    "llama.cpp readiness check failed"
                )


@lru_cache
def get_readiness() -> ReadinessService:
    return ReadinessService()
