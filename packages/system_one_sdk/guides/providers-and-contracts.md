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
