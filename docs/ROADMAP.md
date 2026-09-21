# Implementation sequence

## Phase A — contracts + system_one_sdk 0.6.0

`packages/system_one_contracts` owns provider-neutral v1 request/response/model
contracts, Choice ordering at the protocol seam, error/capability vocabulary,
the inference provider behaviour and reusable provider conformance.

`packages/system_one_sdk` owns the rich semantic/client layer, bridges inference
providers through `SystemOneSDK.Providers.Contract`, retains the hosted TypeSafe
provider, and adds a generic Pristine-backed endpoint provider plus SDK-level
conformance.

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
8. `SystemOneContracts.Conformance` plus rich-SDK integration through the contract adapter.

This is real self-hosted execution with actual tensor weight import, not a
Python-service wrapper. Later add Qwen option/logit scoring as a second
architecture to prove the abstraction is not Laya-specific.

## Phase D — system_one_server 0.1.0

Work in `packages/system_one_server`: `GET /v1/models`, `POST /v1/systemone`,
health/readiness, auth, validation, telemetry, request IDs and resource limits.
The server accepts `SystemOneContracts.Provider` implementations directly: first
a fake provider, then native integration. Its request parser must feed the raw
JSON body through `SystemOneContracts.V1.Request.decode_json/1` so Choice order is
preserved. Programmatic use does not require the server.

## Phase E — lifecycle integration

External `nshkrdotcom/self_hosted_inference_core`: add `:system_one_v1`,
launch/monitor/stop native services, attach to existing compatible services and
return endpoint descriptors. Do not put inference execution in lifecycle management.
