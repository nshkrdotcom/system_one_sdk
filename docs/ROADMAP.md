# Implementation sequence

## Phase A — system_one_sdk 0.6.0

Work in `packages/system_one_sdk`: provider-neutral v1 request/response/model
contracts, Choice ordering, state semantics, error/capability vocabulary,
reusable `SystemOneSDK.Conformance`, hosted TypeSafe conformance and generic
endpoint-provider support. No standalone system_one_contracts.

## Phase B — dependency audit

Audit North-Shore-AI/crucible_safetensors, North-Shore-AI/hf_hub_ex, Bumblebee,
Nx, Axon and EXLA. Determine whether crucible_safetensors 0.2.0 is actually
required; verify immutable artifact/checksum/cache behavior in hf_hub_ex and
ModernBERT/Qwen upstream requirements. Avoid private framework forks.

## Phase C — system_one_bumblebee 0.1.0

Work in `packages/system_one_bumblebee`, in this order:

1. Official/pinned Laya checkpoint and immutable artifact download.
2. SHA-256 verification and safetensors parse.
3. Inventory every checkpoint tensor; map every required tensor to Nx/Axon.
4. Reproduce the exact tokenizer/preprocessor.
5. ModernBERT encoder and Laya-specific decision head.
6. Python oracle intermediate fixtures and CPU numerical parity.
7. EXLA/GPU parity and resident Nx.Serving.
8. SystemOneSDK conformance.

This is real self-hosted execution with actual tensor weight import, not a
Python-service wrapper. Later add Qwen option/logit scoring as a second
architecture to prove the abstraction is not Laya-specific.

## Phase D — system_one_server 0.1.0

Work in `packages/system_one_server`: `GET /v1/models`, `POST /v1/systemone`,
health/readiness, auth, validation, telemetry, request IDs and resource limits.
First a fake provider, then native integration. This optional package exposes
System One over the network; programmatic use does not require it.

## Phase E — lifecycle integration

External `nshkrdotcom/self_hosted_inference_core`: add `:system_one_v1`,
launch/monitor/stop native services, attach to existing compatible services and
return endpoint descriptors. Do not put inference execution in lifecycle management.
