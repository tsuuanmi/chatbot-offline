"""Shared CPU-first retrieval infrastructure."""

import os
from pathlib import Path
from urllib.parse import quote

from haystack.utils import Secret
from haystack_integrations.components.embedders.fastembed import (
    FastembedDocumentEmbedder,
    FastembedTextEmbedder,
)
from haystack_integrations.document_stores.pgvector import PgvectorDocumentStore


def _required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"Required environment variable is missing: {name}")
    return value


def _read_secret(path_env: str) -> str:
    path = Path(_required_env(path_env))

    if not path.is_file():
        raise RuntimeError(f"Secret file does not exist: {path}")

    value = path.read_text(encoding="utf-8").strip()

    if not value:
        raise RuntimeError(f"Secret file is empty: {path}")

    return value


def postgres_connection_string() -> str:
    """Build a PostgreSQL connection string without exposing the password in env."""

    host = _required_env("POSTGRES_HOST")
    port = _required_env("POSTGRES_PORT")
    database = _required_env("POSTGRES_DB")
    user = _required_env("POSTGRES_USER")
    password = _read_secret("POSTGRES_PASSWORD_FILE")

    return (
        "postgresql://"
        f"{quote(user, safe='')}:{quote(password, safe='')}"
        f"@{host}:{port}/{quote(database, safe='')}"
    )


def build_document_store(
    *,
    recreate_table: bool = False,
) -> PgvectorDocumentStore:
    """Create the knowledge document store."""

    return PgvectorDocumentStore(
        connection_string=Secret.from_token(postgres_connection_string()),
        create_extension=False,
        table_name="knowledge_documents",
        language="simple",
        embedding_dimension=int(_required_env("EMBEDDING_DIMENSION")),
        vector_function="cosine_similarity",
        recreate_table=recreate_table,
        search_strategy="exact_nearest_neighbor",
    )


def build_text_embedder() -> FastembedTextEmbedder:
    """Create the CPU query embedder."""

    return FastembedTextEmbedder(
        model=_required_env("EMBEDDING_MODEL"),
        cache_dir=_required_env("FASTEMBED_CACHE_PATH"),
        threads=int(os.environ.get("EMBEDDING_THREADS", "4")),
        progress_bar=False,
        local_files_only=True,
    )


def build_document_embedder() -> FastembedDocumentEmbedder:
    """Create the CPU document embedder used during indexing."""

    return FastembedDocumentEmbedder(
        model=_required_env("EMBEDDING_MODEL"),
        cache_dir=_required_env("FASTEMBED_CACHE_PATH"),
        threads=int(os.environ.get("EMBEDDING_THREADS", "4")),
        batch_size=64,
        progress_bar=False,
        local_files_only=True,
    )
