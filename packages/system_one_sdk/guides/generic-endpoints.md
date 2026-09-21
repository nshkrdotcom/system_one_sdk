# Generic System One endpoints

`SystemOneSDK.Providers.Endpoint` talks directly to any compatible System One v1
HTTP service with:

- `POST /v1/systemone`
- `GET /v1/models`

It uses Pristine directly and does not import TypeSafe OpenAPI/auth semantics.

```elixir
client =
  SystemOneSDK.new_client(
    provider: SystemOneSDK.Providers.Endpoint,
    base_url: "http://127.0.0.1:8080",
    model: "local-model",
    api_key: nil
  )
```

`:api_key` is optional and becomes bearer authentication when present. Custom
headers, transport options, timeout/cancellation and SDK retry overrides remain
available through the normal client/provider options.

For the hosted TypeSafe API, prefer the default `SystemOneSDK.Providers.TypeSafe`
provider so TypeSafe-specific OpenAPI schemas, error handling and authentication
stay in `typesafe_api_sdk`.
