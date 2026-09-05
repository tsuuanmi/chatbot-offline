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
