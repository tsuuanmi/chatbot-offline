# Milestones

## M0 - Clean repository

Establish repository boundaries and architecture rules.

Pass criteria:
- New independent Git repository exists.
- No application code has been copied from the previous chatbot.
- Repository contains only baseline documentation/configuration.
- Docker host requirements are known.

## M1 - Minimal Hayhooks service

Run Hayhooks in Docker with one trivial local pipeline.

No LLM.
No database.
No RAG.

Purpose:
Validate the application server and pipeline deployment model.

## M2 - CPU LLM

Add llama.cpp as an independent service.

Requirements:
- CPU-only reference configuration.
- OpenAI-compatible communication.
- Streaming smoke test.
- No dependency on GPU.

## M3 - PostgreSQL + pgvector

Add a single persistent data service.

Requirements:
- PostgreSQL.
- pgvector.
- migrations.
- health/readiness checks.

## M4 - CPU retrieval

Add local embedding and retrieval.

Candidates:
- FastEmbed / ONNX Runtime.
- pgvector semantic retrieval.
- PostgreSQL full-text search.
- hybrid retrieval.

Benchmark against the previous implementation before accepting it.

## M5 - Forensic behavior

Port only required business logic:

- prepared answers
- figure handling where required
- domain classification
- high-risk classification
- approved-evidence policy
- evidence limitation
- citations

All behavior must be covered by tests.

## M6 - Chat application behavior

Add:

- conversation history
- client ownership
- authentication
- streaming API
- request capacity control

## M7 - Production deployment

Add:

- Nginx
- security hardening
- health/readiness
- resource limits
- structured local logging
- backup/restore

## M8 - Offline distribution

Create:

- offline Docker image bundle
- Python/application dependency bundle where required
- model bundle
- integrity hashes
- installer
- updater
- rollback support

Validate on:
- Ubuntu
- RHEL with SELinux Enforcing

## M9 - Optional GPU acceleration

Add automatic or explicit acceleration without changing application behavior.

CPU remains the required baseline.

## M10 - Production acceptance

Validate:

- clean install
- offline install
- upgrade
- rollback
- backup/restore
- restart/reboot
- CPU performance
- GPU performance
- concurrent clients
- failure handling
- long-running stability
