# Release Acceptance Checklist

The CPU deployment is the mandatory reference release.
NVIDIA GPU acceleration is optional.

## Source acceptance

Required:

- clean Git working tree
- source regression tests pass
- production gateway acceptance passes
- runtime secret audit passes
- offline scripts pass syntax checks
- secret-consuming services have the required supplementary group
- CPU and GPU Compose configurations resolve successfully

Run:

    make release-source-accept

## Release artifacts

Build artifacts only from a clean committed HEAD.

Required CPU artifact:

- offline CPU bundle
- source_state=clean
- source_git_sha matches release HEAD
- checksums verify
- chatbot host port is not published
- no private .env
- no runtime secrets
- no GPU image included

Optional NVIDIA artifact:

- GPU add-on
- same source Git SHA as CPU bundle
- same bundle version
- same architecture
- checksums verify

## Fresh-install acceptance

For each mandatory target platform:

1. install the CPU bundle from a fresh deployment state
2. run offline/manage.sh verify
3. run offline/accept.sh
4. stop and start the deployment
5. run offline/manage.sh verify again

Ubuntu acceptance is mandatory.

RHEL-compatible acceptance must be performed on a real
RHEL/Rocky/AlmaLinux/CentOS host with SELinux Enforcing.
Do not mark this gate complete based on simulation.

## NVIDIA acceptance

When NVIDIA GPU support is shipped:

1. install and verify the CPU deployment first
2. enable the matching GPU add-on
3. verify CUDA is visible to llama-server
4. verify authenticated chat and streaming
5. disable GPU mode
6. verify CPU fallback

GPU acceleration must not change API, authentication,
retrieval, policy, citation, or streaming behavior.

## Performance records

Record, but do not treat as a universal SLA:

- CPU median request latency
- CPU generation or stream throughput
- concurrency baseline
- optional GPU comparison

## Release completion

A multi-platform production release is complete only when:

- source acceptance passes
- clean artifact provenance passes
- fresh Ubuntu CPU acceptance passes
- required RHEL plus SELinux acceptance passes
- optional GPU acceptance passes when included
- release documentation matches the validated behavior
