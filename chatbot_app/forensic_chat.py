"""Policy-controlled forensic chatbot orchestration."""

from __future__ import annotations

import asyncio
import os
from functools import lru_cache
from pathlib import Path

from haystack import Pipeline
from haystack.components.generators.chat import (
    OpenAIChatGenerator,
)
from haystack.dataclasses import ChatMessage
from haystack.utils import Secret

from chatbot_app.citations import (
    citation_ids,
    citation_token,
    sanitize_citations,
)
from chatbot_app.domain import (
    get_domain_classifier,
)
from chatbot_app.evidence import (
    EvidenceItem,
    get_evidence_policy,
)
from chatbot_app.policy import (
    DomainDecision,
    get_domain_policy,
)
from chatbot_app.prepared import (
    PreparedAnswer,
    get_prepared_answers,
)
from chatbot_app.retrieval import (
    get_hybrid_retriever,
)


BASE_SYSTEM_PROMPT = """Bạn là trợ lý AI chuyên về giám định ADN và di truyền pháp y.

Trả lời cùng ngôn ngữ với người dùng.
Trả lời rõ ràng, thận trọng và chính xác.
Không bịa dữ liệu, ngưỡng, SOP, nguồn hoặc kết quả xét nghiệm.
Không suy diễn kết luận nhận dạng, huyết thống hoặc pháp lý từ dữ liệu không được cung cấp.
"""


STANDARD_EVIDENCE_PROMPT = """Các tài liệu bên dưới là nội dung nội bộ đã được phê duyệt để hỗ trợ giải thích, nhưng không mặc nhiên là chứng cứ có thẩm quyền cho kết luận vụ việc.

Chỉ sử dụng chúng khi thực sự liên quan.
Mỗi khẳng định dựa trên tài liệu phải dùng đúng citation dạng [cite:ID].
Không tạo citation ngoài danh sách được cung cấp.
"""


NO_INTERNAL_EVIDENCE_PROMPT = """Không có tài liệu nội bộ phù hợp được chọn cho câu hỏi này.

Bạn có thể giải thích kiến thức nền một cách thận trọng, nhưng không được giả vờ rằng câu trả lời được hỗ trợ bởi nguồn nội bộ và không được tạo citation.
"""


HIGH_RISK_PROMPT = """Đây là yêu cầu rủi ro cao.

Không được đưa ra kết luận cuối cùng về danh tính, quan hệ huyết thống, nghi phạm, giá trị pháp lý, SOP bắt buộc hoặc kết luận vụ việc.

Chỉ được mô tả điều mà chứng cứ có thẩm quyền hỗ trợ, giới hạn của chứng cứ và dữ liệu/SOP cần bổ sung.
Mọi khẳng định dựa trên chứng cứ phải có citation hợp lệ.
"""


OUT_OF_DOMAIN_RESPONSE = (
    "Phạm vi hiện tại của trợ lý chỉ bao gồm giám định ADN "
    "và di truyền pháp y. Tôi không xử lý yêu cầu này trong "
    "pipeline chuyên môn hiện tại."
)


CLARIFICATION_RESPONSE = (
    "Bạn vui lòng cung cấp thêm ngữ cảnh hoặc dữ liệu cụ thể "
    "cần phân tích để tôi có thể xác định đúng yêu cầu trong "
    "phạm vi giám định ADN và di truyền pháp y."
)


HIGH_RISK_LIMITATION_RESPONSE = (
    "Tôi không thể đưa ra kết luận cuối cùng cho yêu cầu này. "
    "Kho tri thức hiện tại chưa có nguồn chuyên môn được cấu "
    "hình là chứng cứ có thẩm quyền cho loại kết luận rủi ro "
    "cao này. Cần sử dụng dữ liệu vụ việc, SOP và nguồn chuyên "
    "môn đã được phê duyệt, cùng đánh giá của người có thẩm quyền."
)


class ForensicChatService:
    """Orchestrate policy, exact answers, retrieval and generation."""

    def __init__(self) -> None:
        self.classifier = get_domain_classifier()
        self.domain_policy = get_domain_policy()
        self.prepared = get_prepared_answers()
        self.retriever = get_hybrid_retriever()
        self.evidence_policy = (
            get_evidence_policy()
        )

        api_key_path = Path(
            os.environ["LLAMA_API_KEY_FILE"]
        )

        api_key = api_key_path.read_text(
            encoding="utf-8"
        ).strip()

        if not api_key:
            raise RuntimeError(
                "llama.cpp API key file is empty"
            )

        generator = OpenAIChatGenerator(
            api_key=Secret.from_token(
                api_key
            ),
            api_base_url=os.environ[
                "LLAMA_BASE_URL"
            ],
            model=os.environ[
                "LLAMA_MODEL_ALIAS"
            ],
            generation_kwargs={
                "temperature": 0.2,
                "max_tokens": 512,
            },
            timeout=600.0,
            max_retries=0,
        )

        self.generation = Pipeline()

        self.generation.add_component(
            "llm",
            generator,
        )

    async def answer(
        self,
        message: str,
    ) -> dict[str, object]:
        query = message.strip()

        if not query:
            raise ValueError(
                "message must not be empty"
            )

        scores = await asyncio.to_thread(
            self.classifier.classify,
            query,
        )

        decision = self.domain_policy.decide(
            query,
            scores,
        )

        prepared = self.prepared.find(
            query
        )

        # Risk must always be evaluated before an exact prepared answer.
        if decision.risk == "high":
            return await self._answer_high_risk(
                query,
                decision,
            )

        # An approved exact match is stronger domain evidence than the
        # semantic domain classifier, but it may never override high risk.
        if prepared is not None:
            return self._prepared_response(
                prepared,
                decision,
            )

        if decision.domain == "out_of_domain":
            return self._fixed_response(
                answer=OUT_OF_DOMAIN_RESPONSE,
                source="out_of_domain",
                decision=decision,
            )

        if decision.domain == "clarify":
            return self._fixed_response(
                answer=CLARIFICATION_RESPONSE,
                source="clarification",
                decision=decision,
            )

        retrieval = await self.retriever.retrieve(
            query
        )

        evidence = self.evidence_policy.select(
            retrieval,
            high_risk=False,
        )

        return await self._generate(
            query,
            decision,
            evidence,
            high_risk=False,
        )

    async def _answer_high_risk(
        self,
        query: str,
        decision: DomainDecision,
    ) -> dict[str, object]:
        # Current corpus intentionally has no authoritative topic.
        if (
            not self.evidence_policy
            .has_authoritative_topics
        ):
            return self._fixed_response(
                answer=HIGH_RISK_LIMITATION_RESPONSE,
                source="evidence_limitation",
                decision=decision,
                evidence_status="insufficient",
            )

        retrieval = await self.retriever.retrieve(
            query
        )

        evidence = self.evidence_policy.select(
            retrieval,
            high_risk=True,
        )

        if not evidence:
            return self._fixed_response(
                answer=HIGH_RISK_LIMITATION_RESPONSE,
                source="evidence_limitation",
                decision=decision,
                evidence_status="insufficient",
            )

        return await self._generate(
            query,
            decision,
            evidence,
            high_risk=True,
        )

    def _prepared_response(
        self,
        prepared: PreparedAnswer,
        decision: DomainDecision,
    ) -> dict[str, object]:
        token = citation_token(
            prepared.citation_id
        )

        return {
            "answer": (
                f"{prepared.answer}\n\n{token}"
            ),
            "source": "prepared_answer",
            "decision": decision.to_dict(),
            "evidence_status": "supporting",
            "citations": [
                prepared.citation()
            ],
        }

    @staticmethod
    def _fixed_response(
        *,
        answer: str,
        source: str,
        decision: DomainDecision,
        evidence_status: str = "not_applicable",
    ) -> dict[str, object]:
        return {
            "answer": answer,
            "source": source,
            "decision": decision.to_dict(),
            "evidence_status": evidence_status,
            "citations": [],
        }

    async def _generate(
        self,
        query: str,
        decision: DomainDecision,
        evidence: list[EvidenceItem],
        *,
        high_risk: bool,
    ) -> dict[str, object]:
        system_parts = [
            BASE_SYSTEM_PROMPT,
        ]

        if high_risk:
            system_parts.append(
                HIGH_RISK_PROMPT
            )

        if evidence:
            system_parts.append(
                STANDARD_EVIDENCE_PROMPT
            )

            system_parts.append(
                self._evidence_context(
                    evidence
                )
            )
        else:
            system_parts.append(
                NO_INTERNAL_EVIDENCE_PROMPT
            )

        messages = [
            ChatMessage.from_system(
                "\n\n".join(system_parts)
            ),
            ChatMessage.from_user(query),
        ]

        result = await self.generation.run_async(
            {
                "llm": {
                    "messages": messages,
                }
            }
        )

        answer = result[
            "llm"
        ]["replies"][0].text

        allowed = {
            item.citation_id
            for item in evidence
        }

        answer = sanitize_citations(
            answer,
            allowed,
        )

        used = citation_ids(answer)

        citations = [
            item.citation()
            for item in evidence
            if item.citation_id in used
        ]

        return {
            "answer": answer,
            "source": "generated",
            "decision": decision.to_dict(),
            "evidence_status": (
                "authoritative"
                if high_risk
                else (
                    "supporting"
                    if evidence
                    else "insufficient"
                )
            ),
            "citations": citations,
        }

    @staticmethod
    def _evidence_context(
        evidence: list[EvidenceItem],
    ) -> str:
        blocks: list[str] = []

        for item in evidence:
            document = item.document
            meta = document.meta
            token = citation_token(
                item.citation_id
            )

            blocks.append(
                "\n".join(
                    (
                        f"{token}",
                        document.content or "",
                        (
                            "Nguồn: "
                            f"{meta.get('source_title') or 'unknown'}"
                        ),
                        (
                            "Phiên bản: "
                            f"{meta.get('source_version') or 'unknown'}"
                        ),
                        (
                            "Mục/trang: "
                            f"{meta.get('source_page_or_section') or 'unknown'}"
                        ),
                    )
                )
            )

        return (
            "Tài liệu nội bộ liên quan:\n\n"
            + "\n\n".join(blocks)
        )


@lru_cache
def get_forensic_chat() -> ForensicChatService:
    return ForensicChatService()
