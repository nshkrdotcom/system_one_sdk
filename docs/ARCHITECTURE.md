# Architecture

Independent Mix projects under `packages/`; no umbrella or root dependency graph.

- Hosted: application → SystemOneSDK → TypeSafe provider → TypeSafeAPISDK → hosted API.
- Planned native: application → SystemOneSDK → SystemOneBumblebee adapter → Nx.Serving.
- Planned network: remote client → HTTP → SystemOneServer → inference provider → model.

The runtime call direction to an adapter is distinct from its compile dependency:
both optional packages depend on the SDK, never the reverse.

SystemOneSDK owns Noul, Choice, Score, preparation, evaluation, response contracts,
batching, telemetry, OTP integration, runtime controls, model helpers and testing.
Provider-neutral v1 contracts and reusable conformance belong here; there will be
no standalone system_one_contracts package.

TypeSafeAPISDK owns TypeSafe HTTP, authentication, defaults, generated operations,
wire schemas, retries, raw HTTP metadata and OpenAPI maintenance.
Native execution and network exposure are optional. Lifecycle management belongs
in the external self_hosted_inference_core project, not the inference runtime.
