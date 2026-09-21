<img src="assets/system_one_server.svg" width="200" height="200" alt="SystemOneServer">

# SystemOneServer

Optional HTTP/network façade for the System One v1 protocol.

**0.1.0 is unpublished. Runtime implementation is under active development.**
This scaffold has documentation and a module-load test, with no runtime API yet.

This package will own network exposure, HTTP validation, authentication and service operations. It does not own shared wire/inference contracts, provider-specific hosted HTTP internals, or lifecycle management. Those belong to
SystemOneContracts, TypeSafeAPISDK and external lifecycle tooling respectively.

## Intended installation (after publication)

```elixir
{:system_one_server, "~> 0.1.0"}
```

For development, run `mix deps.get` and `mix test` from this directory.
The explicit `../system_one_contracts` path dependency is development-only. Replace it with
`{:system_one_contracts, "~> 0.1.0"}` after the contracts package is published; `../../scripts/release_check system_one_server` refuses path dependencies.

## Next implementation

`GET /v1/models`, `POST /v1/systemone`, health/readiness, auth, validation, telemetry, request IDs and resource limits; first a fake provider, then native integration.

Plug/Bandit selection is deferred until the server runtime phase; the v1 contracts now live in SystemOneContracts. No endpoints or listener are implemented. Programmatic hosted and native use do not require this server.

[Contracts](../system_one_contracts/README.md) · [SDK](../system_one_sdk/README.md) · [Bumblebee](../system_one_bumblebee/README.md) · [Server](../system_one_server/README.md) · [Repository](../../README.md)

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
