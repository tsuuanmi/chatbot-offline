ARG HAYHOOKS_IMAGE=deepset/hayhooks@sha256:2d657aa5499f440ccae17c860d35d1d709095b385da3ec9338ebc0decdb37ce9
FROM ${HAYHOOKS_IMAGE}

USER root

COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

ARG EMBEDDING_MODEL
ARG EMBEDDING_DIMENSION

ENV EMBEDDING_MODEL=${EMBEDDING_MODEL} \
    EMBEDDING_DIMENSION=${EMBEDDING_DIMENSION} \
    FASTEMBED_CACHE_PATH=/opt/models/fastembed

# Download the embedding model once while building the release image.
RUN python - <<'PY'
import os

from fastembed import TextEmbedding

model = TextEmbedding(
    model_name=os.environ["EMBEDDING_MODEL"],
    cache_dir=os.environ["FASTEMBED_CACHE_PATH"],
)

embedding = next(iter(model.embed(["kiểm tra mô hình embedding"])))

expected = int(os.environ["EMBEDDING_DIMENSION"])
actual = len(embedding)

if actual != expected:
    raise RuntimeError(
        f"Unexpected embedding dimension: expected={expected}, actual={actual}"
    )

print(f"Embedding model ready: dimension={actual}")
PY

COPY chatbot_app /app/chatbot_app
COPY tools /app/tools

ENV PYTHONPATH=/app \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1
