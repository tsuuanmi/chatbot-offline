# Chatbot Offline Roadmap

## Mission

Build a clean, production-ready, fully offline Vietnamese chatbot for forensic genetics and DNA workflows.

CPU-only behavior is the reference baseline. GPU acceleration is optional and must never change policy, retrieval, citation, safety, authentication, ownership, or output semantics.

Target platforms:

- Ubuntu
- RHEL with SELinux Enforcing

---

## Core Architecture

Long-running services:

1. Nginx — from M7 onward
2. Chatbot / Hayhooks
3. llama.cpp
4. PostgreSQL + pgvector

One-shot services:

- database migrations
- knowledge indexing
- installation / validation utilities

Key principles:

- fully offline runtime
- CPU-first
- llama.cpp primary inference
- PostgreSQL + pgvector
- FastEmbed / ONNX CPU embeddings
- PostgreSQL keyword retrieval
- RRF hybrid fusion
- versioned migrations only
- no startup DDL
- secrets through mounted files
- SELinux stays Enforcing
- Nginx is the only configurable LAN-facing HTTP gateway from M7 onward

---

## Safety Invariants

- Risk policy runs before prepared answers.
- High-risk requests without authoritative evidence return deterministic evidence limitation.
- High-risk requests must not call the LLM when authoritative evidence is unavailable.
- Conversation history is context, not evidence.
- Historical citations are not automatically valid for the current turn.
- History must never downgrade current risk.
- Only `[cite:ID]` is treated as a citation token.
- Conversation ownership must come from authenticated identity.
- Clients must never supply trusted `owner_id`.
- Authentication secrets must never appear in pipeline request parameters or logs.

---

# Milestones

## M0 — Clean Repository

Status: COMPLETE

## M1 — Minimal Hayhooks / Haystack Runtime

Status: COMPLETE

## M2 — llama.cpp CPU Chat Runtime

Status: COMPLETE

## M3 — PostgreSQL + pgvector

Status: COMPLETE

## M4 — FastEmbed CPU + Hybrid Retrieval

Status: COMPLETE

## M5 — Forensic Domain, Risk, Evidence and RAG

Status: COMPLETE

Includes:

- domain/risk routing
- explicit high-risk rules
- prepared answers
- hybrid retrieval
- evidence policy
- citation validation
- deterministic high-risk limitation
- calibration suites

---

## M6 — Conversation, Identity and API

### M6A — Conversation Persistence and Context

Status: COMPLETE

Implemented:

- client-generated conversation UUID
- persistent PostgreSQL conversations
- persistent turns
- explicit transactions
- advisory transaction locks
- bounded history
- bounded context size
- citation stripping from historical answers
- contextual follow-up handling
- contextual high-risk protection
- UUID API validation
- stateless backward compatibility
- restart persistence
- concurrent turn allocation acceptance
- readiness endpoint

Acceptance:

```text
make verify
make accept
make recovery
```

### M6B — Authentication and Ownership

Status: COMPLETE

#### M6B.1 — Authentication Primitive

Status: COMPLETE

Requirements:

* fully offline
* FastAPI/Hayhooks middleware
* Authorization header
* mounted auth registry secret
* timing-safe credential verification
* no raw key in chatbot container config
* missing auth -> 401
* invalid auth -> 401
* runtime deploy/undeploy disabled
* restrictive CORS
* authenticated request identity available through request context

#### M6B.2 — Authenticated Ownership

Status: COMPLETE

Requirements:

* remove static `CHAT_OWNER_ID`
* derive owner from authenticated identity
* owner A cannot access owner B conversations
* client cannot submit `owner_id`
* foreign conversation access must not leak ownership details

#### M6B.3 — Auth Hardening

Status: COMPLETE

Requirements:

* multi-user auth registry
* rotation workflow
* startup validation
* malformed registry rejection
* log audit
* restart acceptance
* offline acceptance

### M6C — Streaming API

Status: COMPLETE

Goals:

* streaming responses
* cancellation handling
* bounded buffering
* atomic persistence only after completed generation
* correct citation handling

---

## M7 — Nginx and Production Hardening

Status: COMPLETE


Goals:

* Nginx reverse proxy
* rate limiting
* request size limits
* timeout policy
* security headers
* production CORS
* non-root chatbot runtime
* resource limits
* graceful shutdown
* liveness/readiness separation
* log privacy
* runtime management endpoints disabled

No external exposure before M7 is complete.

---

## M8 — Fully Offline Distribution

Status: IN PROGRESS — implementation complete; real RHEL + SELinux Enforcing acceptance pending

Goals:

* reproducible offline bundle
* pinned runtime images
* pinned model files
* checksums
* one portable installation workflow for Ubuntu and RHEL
* SELinux Enforcing-safe deployment
* no network pulls during installation
* minimal offline operations: start, stop, status, logs, reindex, and verify
* safe refusal when persistent database state exists but credentials are missing

---

M8.1 — offline runtime bundle: COMPLETE

M8.2 — fresh offline installation: COMPLETE

M8.3 — offline operations: COMPLETE

Ubuntu platform acceptance: COMPLETE

RHEL + SELinux Enforcing acceptance: PENDING

## M9 — Optional GPU

Status: COMPLETE

Requirements:

* optional NVIDIA CUDA profile: COMPLETE
* CPU fallback remains available: COMPLETE
* identical behavioral acceptance: COMPLETE
* measurable performance benefit: COMPLETE
* optional offline NVIDIA GPU add-on: COMPLETE

Pre-MTP M9 reference measurement on Quadro RTX 5000:

* CPU median total latency: 15.51 s
* GPU median total latency: 2.97 s
* total latency speedup: 5.22x
* CPU median stream rate: 105.9 chars/s
* GPU median stream rate: 548.2 chars/s
* stream-rate speedup: 5.18x

The CPU runtime remains the mandatory reference deployment.
GPU acceleration is optional and does not alter API, policy,
retrieval, authentication, or streaming semantics.

---

## M10 — Final Cleanup and Release Acceptance

Status: IN PROGRESS — internal release gates complete; real RHEL + SELinux Enforcing acceptance pending

Completed:

* dead-code and tooling canonicalization
* dependency audit
* runtime secret audit
* Ubuntu acceptance
* CPU performance baseline
* concurrency baseline
* restart and persistent-state recovery acceptance
* clean release artifact provenance verification
* CPU/GPU artifact pair verification
* fresh offline installation acceptance
* installer rerun/idempotence acceptance
* offline restart acceptance
* NVIDIA GPU enable acceptance
* CPU fallback acceptance
* Gemma 4 MTP speculative decoding
* production release checklist

Pending external gate:

* real RHEL-compatible host acceptance with SELinux Enforcing

MTP release configuration:

* speculative type: `draft-mtp`
* draft length: 2 tokens
* CPU draft GPU layers: 0
* NVIDIA draft GPU layers: 99
* CPU remains the mandatory reference deployment

Canonical CPU MTP performance baseline:

* median stream rate: 143.9 chars/s
* two-client aggregate stream rate: 143.4 chars/s
* two-client median request latency: 14.28 s
* two-client p95 request latency: 21.01 s
* two-client median TTFT: 3.33 s

These measurements describe the validated host and are not universal SLAs.

---

## Current Acceptance Commands

Source regression:

```bash
make verify
```

Full source acceptance:

```bash
make accept
```

Persistent-state recovery:

```bash
make recovery
```

Performance:

```bash
python3 -m tools.bench stream --label LABEL
python3 -m tools.bench concurrency --label LABEL --clients 2
```

Offline deployment:

```bash
./offline/manage.sh verify
./offline/manage.sh accept
./offline/manage.sh restart
```

Release artifacts:

```bash
python3 -m tools.release build cpu --version VERSION
python3 -m tools.release build gpu --version VERSION
python3 -m tools.release verify pair CPU_BUNDLE GPU_ADDON
```

---

## Deliberately Excluded From Core

Do not add without a concrete requirement:

* MCP
* autonomous agents
* Internet tools
* web browsing
* Redis
* Celery
* generic admin platform
* Open WebUI
* generic workflow engine

---

## Roadmap Maintenance Rule

Update this file whenever:

* milestone status changes
* architecture invariants change
* major dependencies change
* acceptance requirements change
* production constraints change

GitHub HEAD plus this file should be treated as the project source of truth.
