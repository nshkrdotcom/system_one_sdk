# Providers and contracts

SystemOneSDK has two deliberately different provider boundaries.

`SystemOneSDK.Provider` is the **client-side** execution contract. It lets the
rich SDK call a hosted API, a generic HTTP endpoint, or an adapter around a local
runtime while retaining preparation, enrichment, batching, telemetry and OTP
features.

`SystemOneContracts.Provider` is the **inference-side** contract shared with
native runtimes and servers. It receives a provider-neutral v1 request DTO and
returns provider-neutral response/model DTOs. It does not depend on SystemOneSDK.

`SystemOneSDK.Providers.Contract` bridges an inference provider into the rich SDK:

```elixir
client =
  SystemOneSDK.new_client(
    provider: SystemOneSDK.Providers.Contract,
    provider_opts: [
      inference_provider: MyInferenceProvider,
      inference_state: serving,
      model: "my-model"
    ]
  )
```

The optional `system_one_prepared/4` client-provider callback lets this bridge
receive the exact prepared question representation, including Choice order.
Existing providers only implementing `system_one/4` continue to work through the
fallback path.

For text and numeric extraction, an adapter supplies `text` and `number` answer
objects with a `value` key. Use JSON null for an unanswered field. An answer may
include `span` as an ordered pair of offsets and `confidence` and `p_null` as
probabilities. Preserve `valid` and `complete` flags when the provider reports
them. The adapter translates provider-specific routes and payloads.

Advertise `question:text` and `question:number` on each model that supports both
field types. `SystemOneSDK.Conformance.run(client, profile: :extraction)` checks
the selected model's catalog entry and checks the values it extracts from a
short invoice fixture.
