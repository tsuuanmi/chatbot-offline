# Release Acceptance Checklist

CPU execution is mandatory. NVIDIA GPU acceleration is optional and must not change application behavior.

Only one `chatbot` deployment is intended to be active on a host at a time.

## Source acceptance

Required before building a release:

- clean committed Git HEAD
- unit tests pass
- runtime acceptance passes
- persistent-state recovery passes
- runtime secret audit passes
- Python and shell syntax checks pass
- no obsolete CPU-bundle/GPU-add-on release implementation remains

Canonical commands:

```bash
make test
make verify
make accept
make recovery
git status --short
```

## Universal runtime artifact

Build only from a clean committed HEAD:

```bash
make release
```

The runtime artifact is one ZIP:

```text
chatbot-<version>.zip
```

It contains both CPU and NVIDIA execution paths and must include:

- chatbot image
- llama.cpp CPU image
- llama.cpp NVIDIA GPU image
- PostgreSQL + pgvector image
- Nginx image
- Compose configuration
- database migrations
- knowledge indexing tooling
- approved documents
- offline installation and management tooling
- release manifest
- SHA256 checksums

It must not contain:

- GGUF model files
- private `.env`
- runtime secrets
- persisted PostgreSQL data

All chatbot runtime images use the same release version:

```text
chatbot-app:<version>
chatbot-llama-cpu:<version>
chatbot-llama-gpu:<version>
chatbot-postgres:<version>
chatbot-nginx:<version>
```

Verify:

```bash
python3 -m tools.release verify runtime dist/chatbot-<version>.zip
```

## Independent model artifact

Models have an independent lifecycle and are rebuilt only when the required model set changes.

Build:

```bash
make release-models
```

Artifact:

```text
chatbot-models-<model-version>.zip
```

It contains:

- main Gemma GGUF
- Gemma MTP GGUF
- model manifest
- SHA256 checksums

The model package uses ZIP64 stored entries rather than recompressing GGUF files.

Verify:

```bash
python3 -m tools.release verify models dist/chatbot-models-<model-version>.zip
```

The runtime manifest identifies the exact required model bundle and model filenames. Missing or mismatched models must fail clearly rather than silently using another model version.

## Persistent target state

Versioned runtime release directories are disposable.

Persistent models and secrets are stored outside them:

```text
~/.local/share/chatbot/
├── models/
└── state/
    └── secrets/
```

The default PostgreSQL data volume is:

```text
chatbot_postgres_data
```

Runtime code upgrades must preserve:

- installed model bundle
- authentication registry
- client API key
- llama API key
- PostgreSQL password
- PostgreSQL data volume

## Fresh offline installation

The target currently assumes these host prerequisites already exist:

- Docker Engine
- Docker Compose plugin
- Python 3
- make
- ZIP extraction support

Fully offline operating-system/bootstrap dependency installation is future work and is not part of the current runtime artifact.

For the first deployment, copy the runtime ZIP and required model ZIP to the target. Extract the runtime ZIP and run:

```bash
make install
```

Required behavior:

1. verify runtime checksums and architecture
2. install or reuse the exact required model bundle
3. load all Docker images from local archives
4. perform no network pull or download
5. automatically select NVIDIA GPU when Docker exposes CUDA, otherwise CPU
6. allow explicit CPU or GPU selection
7. generate or reuse persistent secrets
8. migrate PostgreSQL
9. build the knowledge index
10. start exactly one `chatbot` runtime
11. verify the authenticated deployment
12. report local and detected LAN URLs

The production gateway binds to `0.0.0.0` by default. A local-only deployment may explicitly override the bind address.

## Installer rerun and code-only upgrade

Running `make install` again must be idempotent.

When the required model bundle is already installed, the model ZIP is not required for a code-only update.

An in-place runtime upgrade must:

- reuse the persistent model store
- reuse persistent secrets
- reuse the PostgreSQL volume
- stop and remove the previous chatbot containers
- start the new runtime using the same `chatbot` Compose project
- leave exactly four long-running containers
- verify the new runtime before final completion
- remove superseded chatbot image versions after successful installation

Validated long-running container names:

```text
chatbot-app
chatbot-llama
chatbot-postgres
chatbot-proxy
```

Ubuntu in-place upgrade acceptance has verified that secrets and the PostgreSQL volume remain unchanged while the active runtime and image version are replaced.

## CPU and NVIDIA acceptance

The same runtime artifact supports both execution modes.

Canonical target commands:

```bash
make cpu
make verify

make gpu
make verify
```

GPU mode must verify an actual CUDA device through Docker. Forced GPU mode must fail clearly when CUDA is unavailable. Automatic mode falls back to CPU.

CPU fallback and NVIDIA GPU enable acceptance are complete on the validated Ubuntu/NVIDIA host.

## Persistent-state recovery

Required behavior:

1. persist an authenticated conversation
2. restart PostgreSQL
3. restart chatbot
4. continue the same conversation
5. recover previous history
6. preserve turn numbering
7. preserve contextual safety behavior

Canonical source command:

```bash
make recovery
```

Persistent-state recovery acceptance is complete.

## Runtime performance record

Performance values are regression references, not universal SLAs.

Validated CPU MTP baseline:

- median stream rate: 143.9 chars/s
- two-client aggregate stream rate: 143.4 chars/s
- two-client median request latency: 14.28 s
- two-client p95 request latency: 21.01 s
- two-client median TTFT: 3.33 s

## MTP configuration

Current production configuration:

- `MTP_MODEL_NAME=mtp-gemma-4-E2B-it.gguf`
- `LLAMA_SPEC_TYPE=draft-mtp`
- `LLAMA_SPEC_DRAFT_N_MAX=2`
- CPU draft offload: 0 GPU layers
- NVIDIA draft offload: 99 GPU layers

The MTP model is distributed in the independent model package, not the runtime ZIP.

## RHEL and SELinux acceptance

This gate must run on a real RHEL-compatible host with SELinux Enforcing.

Required:

- RHEL, Rocky Linux, AlmaLinux, or supported compatible host
- SELinux reports `Enforcing`
- bind mounts operate with the required SELinux labels
- fresh offline installation passes
- installer rerun passes
- code-only in-place upgrade passes
- `make verify` passes
- `make accept` passes
- restart passes
- CPU mode passes
- NVIDIA mode passes when supported by that host
- no workaround disables SELinux enforcement

This gate is currently **PENDING**.

Do not mark multi-platform release acceptance complete based on Ubuntu-only testing.

## Release completion

Internal implementation and Ubuntu release acceptance are complete.

A multi-platform production release is complete only when:

- final runtime artifact is built from the final clean HEAD
- final runtime provenance and checksums pass
- required model package verifies independently
- Ubuntu fresh installation and in-place upgrade acceptance pass
- CPU and optional NVIDIA paths pass
- real RHEL + SELinux Enforcing acceptance passes
- documentation matches validated behavior
