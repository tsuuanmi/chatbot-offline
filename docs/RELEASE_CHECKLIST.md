# Release Acceptance Checklist

The CPU deployment is the mandatory reference release.
NVIDIA GPU acceleration is optional and must not alter behavior.

## Source acceptance

Required:

- clean committed Git HEAD
- `make verify` passes
- `make accept` passes
- `make recovery` passes
- runtime secret audit passes
- secret-group checks pass
- Python and shell syntax checks pass
- no obsolete release or acceptance tooling remains

Canonical commands:

```bash
make verify
make accept
make recovery
```

## Runtime performance record

Performance is recorded for regression visibility.
It is not a universal SLA.

Canonical benchmark interface:

```bash
CHAT_CLIENT_API_KEY_FILE=runtime/secrets/chat_api_key \
python3 -m tools.bench stream \
  --label cpu-mtp-n2

CHAT_CLIENT_API_KEY_FILE=runtime/secrets/chat_api_key \
python3 -m tools.bench concurrency \
  --label cpu-mtp-n2-c2 \
  --clients 2
```

Validated CPU MTP baseline:

- median stream rate: 143.9 chars/s
- two-client aggregate stream rate: 143.4 chars/s
- two-client median request latency: 14.28 s
- two-client p95 request latency: 21.01 s
- two-client median TTFT: 3.33 s

These values describe the validated host only.

## MTP configuration

Current production configuration:

- `MTP_MODEL_NAME=mtp-gemma-4-E2B-it.gguf`
- `LLAMA_SPEC_TYPE=draft-mtp`
- `LLAMA_SPEC_DRAFT_N_MAX=2`
- CPU draft offload: 0 GPU layers
- NVIDIA draft offload: 99 GPU layers

The MTP model is included in the CPU offline bundle.

## Release artifacts

Artifacts must be built only from a clean committed HEAD.

Build:

```bash
python3 -m tools.release build cpu --version VERSION
python3 -m tools.release build gpu --version VERSION
```

Required CPU artifact checks:

- `source_state=clean`
- `source_git_sha` matches release HEAD
- architecture matches the target
- checksums verify
- main GGUF model is included
- MTP GGUF model is included
- manifest configuration matches shipped configuration
- chatbot host port is not published
- no private `.env`
- no runtime secrets
- no GPU image in the CPU bundle

Optional NVIDIA add-on checks:

- same source Git SHA as CPU bundle
- same bundle version
- same architecture
- checksums verify
- NVIDIA llama.cpp image is included

Verify:

```bash
python3 -m tools.release verify cpu CPU_BUNDLE
python3 -m tools.release verify gpu GPU_ADDON
python3 -m tools.release verify pair CPU_BUNDLE GPU_ADDON
```

## Fresh Ubuntu installation acceptance

Required:

1. install from a fresh deployment state
2. verify authenticated runtime
3. run platform acceptance
4. rerun the installer without deleting state
5. verify installer idempotence
6. restart the deployment
7. verify runtime again

Canonical commands inside the installed bundle:

```bash
./offline/install.sh
./offline/manage.sh verify
./offline/manage.sh accept

./offline/install.sh

./offline/manage.sh restart
./offline/manage.sh verify
./offline/manage.sh accept
```

Ubuntu acceptance is complete.

## Persistent-state recovery

Required behavior:

1. persist an authenticated conversation turn
2. restart PostgreSQL
3. restart chatbot
4. continue the same conversation
5. previous history is recovered
6. turn numbering remains correct
7. contextual safety behavior remains intact

Canonical source command:

```bash
make recovery
```

Persistent-state recovery acceptance is complete.

## NVIDIA acceptance

When the NVIDIA add-on is shipped:

1. establish a verified CPU deployment
2. enable the matching GPU add-on
3. verify CUDA is visible
4. verify authenticated runtime behavior
5. verify GPU image and device request
6. disable GPU mode
7. verify CPU fallback

Canonical commands:

```bash
./offline/manage.sh gpu enable GPU_ADDON
./offline/manage.sh gpu status
./offline/manage.sh verify
./offline/manage.sh accept

./offline/manage.sh gpu disable
./offline/manage.sh verify
./offline/manage.sh accept
```

GPU enable and CPU fallback acceptance are complete
on the validated NVIDIA host.

## RHEL and SELinux acceptance

This gate must run on a real RHEL-compatible host
with SELinux Enforcing.

Required:

- RHEL, Rocky Linux, AlmaLinux, or supported compatible host
- SELinux reports `Enforcing`
- bind mounts operate with required SELinux labels
- fresh CPU installation passes
- installer rerun passes
- `offline/manage.sh verify` passes
- `offline/manage.sh accept` passes
- restart passes
- no workaround disables SELinux enforcement

This gate is currently **PENDING**.

Do not mark multi-platform release acceptance complete
based on simulation or Ubuntu-only testing.

## Release completion

Internal implementation and Ubuntu release acceptance
are complete.

A multi-platform production release is complete only when:

- final artifacts were built from the final clean HEAD
- CPU/GPU pair provenance passes
- Ubuntu acceptance passes
- real RHEL + SELinux Enforcing acceptance passes
- optional NVIDIA acceptance passes when shipped
- documentation matches validated behavior
