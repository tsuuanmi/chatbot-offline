# chatbot-offline

Clean, production-oriented offline chatbot for forensic genetics.

## Goals

- Fully functional without Internet access at runtime.
- CPU is the reference and mandatory execution path.
- GPU acceleration is optional.
- Supports Ubuntu and Red Hat Enterprise Linux.
- Reproducible Docker-based deployment.
- Minimal number of long-running services.
- Explicit, testable forensic domain and risk policies.
- Local retrieval with approved evidence and citations.
- Simple offline installation, update, backup, and rollback.

## Non-goals

The core system does not require:

- web search
- MCP
- autonomous agents
- external cloud APIs
- plugin marketplaces
- workflow editors
- Redis
- Celery
- Kubernetes
- a bundled general-purpose chat UI

These may only be introduced later if a concrete requirement justifies them.

## Migration policy

`../chatbot` is a reference implementation, not the base of this repository.

Code, configuration, data, or assets from the old repository are copied only
when a milestone requires them. Bulk copying is not allowed.

Each migrated component should be simplified for the new architecture instead
of preserving obsolete compatibility or infrastructure.

## Development Roadmap

The project is being built incrementally toward a production-ready, fully offline Vietnamese forensic genetics chatbot.

Core architectural requirements:

* Fully offline runtime.
* CPU-first reference implementation; GPU acceleration is optional.
* llama.cpp for local inference.
* PostgreSQL + pgvector for persistence and semantic retrieval.
* FastEmbed / ONNX CPU embeddings.
* PostgreSQL full-text search + semantic search fused with RRF.
* Versioned database migrations only; application startup must not perform DDL.
* Secrets must be supplied through mounted secret files and must never be committed or logged.
* RHEL deployments must support SELinux Enforcing.
* Nginx is the configurable LAN-facing gateway; direct chatbot host access remains loopback-only for local maintenance and testing.
* Conversation history is context only and must never be treated as authoritative evidence.
* High-risk policy always takes precedence over prepared answers and generation.
* Conversation ownership must come from authenticated identity, never from a client-supplied owner ID.

### Milestone Status

* M0 — Clean repository: COMPLETE
* M1 — Minimal Hayhooks / Haystack runtime: COMPLETE
* M2 — llama.cpp CPU chat runtime: COMPLETE
* M3 — PostgreSQL + pgvector: COMPLETE
* M4 — FastEmbed CPU + hybrid retrieval: COMPLETE
* M5 — Forensic domain, risk, evidence, prepared answers, citations and RAG: COMPLETE
* M6A — Conversation persistence and bounded conversational context: COMPLETE
* M6B.1 — Offline API authentication: COMPLETE
* M6B.2 — Authenticated conversation ownership: COMPLETE
* M6B.3 — Authentication hardening: COMPLETE
* M6C — Streaming API: COMPLETE
* M7 — Nginx and production hardening: COMPLETE
* M8 — Fully offline distribution for Ubuntu and RHEL: IN PROGRESS — Ubuntu validated; RHEL/SELinux acceptance pending
* M9 — Optional NVIDIA GPU acceleration: COMPLETE
* M10 — Final cleanup and release acceptance: PENDING

### Current Acceptance Commands

Common regression:

```
make verify
```

Conversation persistence and context:

```
make smoke-history
make smoke-history-context
make smoke-history-concurrency
```

Authentication:

```
make smoke-auth
make smoke-api-contract
```

Authenticated ownership:

```
make smoke-ownership
```

Runtime readiness:

```
make ready
```

Offline restart:

```
make offline-restart
make ready
```

Image consistency:

```
make image-info
```

### Production Safety Invariants

1. Risk classification runs before prepared-answer selection.
2. High-risk requests without authoritative evidence return a deterministic evidence-limitation response and do not call the LLM.
3. Conversation history is not evidence.
4. Historical citations are not automatically valid for a new request.
5. Conversation history must never downgrade current risk.
6. Only explicit `[cite:ID]` tokens are interpreted as citations.
7. Authentication credentials must not be pipeline request parameters.
8. Conversation owner identity must be derived from authentication.
9. Runtime pipeline deployment and undeployment must not be exposed in production.
10. External HTTP access must enter through Nginx; direct chatbot host access remains loopback-only.

### Deliberately Excluded From Core

The core application should remain focused and should not add the following without a concrete requirement and architectural review:

* MCP
* autonomous agents
* Internet or web-browsing tools
* Redis
* Celery
* generic admin platforms
* Open WebUI
* generic workflow engines

Update this section whenever a milestone changes status or a major architectural or production constraint changes.
