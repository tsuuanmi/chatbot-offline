"""CPU-first hybrid forensic knowledge retrieval."""

from typing import Any

from haystack.components.joiners import DocumentJoiner
from haystack import Pipeline
from hayhooks import BasePipelineWrapper
from haystack_integrations.components.retrievers.pgvector import (
    PgvectorEmbeddingRetriever,
    PgvectorKeywordRetriever,
)

from chatbot_app.retrieval import (
    build_document_store,
    build_text_embedder,
)


def serialize_document(document: Any) -> dict[str, Any]:
    return {
        "id": document.id,
        "score": (
            float(document.score)
            if document.score is not None
            else None
        ),
        "content": document.content,
        "meta": {
            "no": document.meta.get("no"),
            "term": document.meta.get("term"),
            "topic": document.meta.get("topic"),
            "figure_id": document.meta.get("figure_id"),
            "source_id": document.meta.get("source_id"),
            "source_title": document.meta.get("source_title"),
            "source_authority": document.meta.get("source_authority"),
            "source_page_or_section": document.meta.get(
                "source_page_or_section"
            ),
            "approval_status": document.meta.get("approval_status"),
        },
    }


class PipelineWrapper(BasePipelineWrapper):
    """Hybrid semantic + keyword retrieval."""

    skip_mcp = True

    def setup(self) -> None:
        document_store = build_document_store()

        pipeline = Pipeline()

        pipeline.add_component(
            "embedder",
            build_text_embedder(),
        )

        pipeline.add_component(
            "semantic",
            PgvectorEmbeddingRetriever(
                document_store=document_store,
                top_k=8,
            ),
        )

        pipeline.add_component(
            "keyword",
            PgvectorKeywordRetriever(
                document_store=document_store,
                top_k=8,
            ),
        )

        pipeline.add_component(
            "joiner",
            DocumentJoiner(
                join_mode="reciprocal_rank_fusion",
                top_k=5,
            ),
        )

        pipeline.connect(
            "embedder.embedding",
            "semantic.query_embedding",
        )

        pipeline.connect(
            "semantic.documents",
            "joiner.documents",
        )

        pipeline.connect(
            "keyword.documents",
            "joiner.documents",
        )

        self.pipeline = pipeline

    async def run_api_async(
        self,
        query: str,
    ) -> dict[str, list[dict[str, Any]]]:
        result = await self.pipeline.run_async(
            {
                "embedder": {
                    "text": query,
                },
                "keyword": {
                    "query": query,
                },
            },
            include_outputs_from={
                "semantic",
                "keyword",
            },
        )

        return {
            "hybrid": [
                serialize_document(document)
                for document in result["joiner"]["documents"]
            ],
            "semantic": [
                serialize_document(document)
                for document in result["semantic"]["documents"]
            ],
            "keyword": [
                serialize_document(document)
                for document in result["keyword"]["documents"]
            ],
        }
