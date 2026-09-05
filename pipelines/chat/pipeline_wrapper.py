"""Minimal CPU-first chat pipeline backed by llama.cpp."""

import os
from pathlib import Path

from haystack import Pipeline
from haystack.components.generators.chat import OpenAIChatGenerator
from haystack.dataclasses import ChatMessage
from haystack.utils import Secret
from hayhooks import BasePipelineWrapper


SYSTEM_PROMPT = """Bạn là trợ lý AI về giám định ADN và di truyền pháp y.
Trả lời cùng ngôn ngữ với người dùng.
Trả lời rõ ràng và ngắn gọn.
Nếu không biết, hãy nói rằng bạn không biết.
"""


class PipelineWrapper(BasePipelineWrapper):
    """Minimal Haystack -> llama.cpp pipeline."""

    skip_mcp = True

    def setup(self) -> None:
        api_key_path = Path(os.environ["LLAMA_API_KEY_FILE"])
        api_key = api_key_path.read_text(encoding="utf-8").strip()

        if not api_key:
            raise RuntimeError("llama.cpp API key file is empty")

        generator = OpenAIChatGenerator(
            api_key=Secret.from_token(api_key),
            api_base_url=os.environ["LLAMA_BASE_URL"],
            model=os.environ["LLAMA_MODEL_ALIAS"],
            generation_kwargs={
                "temperature": 0.2,
                "max_tokens": 256,
            },
            timeout=600.0,
            max_retries=0,
        )

        pipeline = Pipeline()
        pipeline.add_component("llm", generator)

        self.pipeline = pipeline

    async def run_api_async(self, message: str) -> dict[str, str]:
        messages = [
            ChatMessage.from_system(SYSTEM_PROMPT),
            ChatMessage.from_user(message),
        ]

        result = await self.pipeline.run_async(
            {
                "llm": {
                    "messages": messages,
                }
            }
        )

        return {
            "response": result["llm"]["replies"][0].text,
        }
