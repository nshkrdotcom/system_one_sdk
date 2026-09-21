# Architecture

Independent Mix projects under `packages/`; no umbrella or root dependency graph.

- Contracts: SystemOneContracts defines the small provider-neutral `system-one/v1` wire and inference-provider seam.
- Hosted: application → SystemOneSDK → TypeSafe provider → TypeSafeAPISDK → hosted API.
- Generic network client: application → SystemOneSDK → Endpoint provider → compatible System One HTTP service.
- Planned native: application → SystemOneSDK → Contract adapter → SystemOneBumblebee → Nx.Serving.
- Planned network service: remote client → HTTP → SystemOneServer → SystemOneContracts.Provider → model.

Compile dependencies point inward toward the small contracts package.
`system_one_bumblebee` and `system_one_server` do not depend on the rich SDK.
The rich SDK depends on contracts so it can bridge native inference providers
without making those providers depend back on SDK features.

SystemOneSDK owns Noul, Choice, Score, preparation, evaluation, response
contracts, batching, telemetry, OTP integration, runtime controls, model helpers,
client-provider adapters and high-level testing/conformance.

SystemOneContracts owns v1 request/response/model DTOs, ordered question entries,
stable capability/error vocabularies, the inference-side provider behaviour and
provider-level conformance. It owns no HTTP stack, model runtime or lifecycle.

TypeSafeAPISDK owns TypeSafe HTTP, authentication, defaults, generated
operations, TypeSafe wire schemas, retries, raw HTTP metadata and OpenAPI
maintenance. Native execution and network exposure are optional. Lifecycle
management belongs in the external self_hosted_inference_core project, not the
inference runtime.
