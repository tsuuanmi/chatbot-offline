"""Policy-controlled forensic chat endpoint."""

from uuid import UUID

from hayhooks import BasePipelineWrapper

from chatbot_app.forensic_chat import (
    get_forensic_chat,
)


class PipelineWrapper(BasePipelineWrapper):
    skip_mcp = True

    def setup(self) -> None:
        self.chat = get_forensic_chat()

    async def run_api_async(
        self,
        message: str,
        conversation_id: UUID | None = None,
    ) -> dict[str, object]:
        return await self.chat.answer(
            message,
            conversation_id=(
                str(conversation_id)
                if conversation_id
                is not None
                else None
            ),
        )
