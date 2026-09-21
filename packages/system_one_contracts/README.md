# SystemOneContracts

Provider-neutral System One v1 wire contracts and the inference-side provider
behaviour shared by SDKs, native runtimes, and network servers.

This package is deliberately small. It does **not** contain HTTP, authentication,
retry policy, Nx/Bumblebee execution, lifecycle management, batching, telemetry
or the rich semantic conveniences from `system_one_sdk`.

## Installation

```elixir
{:system_one_contracts, "~> 0.1.0"}
```

## Ownership

`SystemOneContracts` owns:

- the `system-one/v1` protocol identifier;
- request, response, usage and model DTOs;
- ordered question entries at the protocol boundary;
- stable capability names;
- normalized provider error categories;
- the inference-side `SystemOneContracts.Provider` behaviour;
- reusable conformance checks for inference providers.

Client-side transport providers remain in `system_one_sdk`. The TypeSafe HTTP API
remains in `typesafe_api_sdk`. Native model execution belongs in packages such as
`system_one_bumblebee`; HTTP serving belongs in `system_one_server`.

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
