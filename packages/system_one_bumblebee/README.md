<img src="assets/system_one_bumblebee.svg" width="200" height="200" alt="SystemOneBumblebee">

# SystemOneBumblebee

Optional native BEAM/Nx/Bumblebee implementation of System One inference.

**0.1.0 is unpublished. Runtime implementation is under active development.**
This scaffold has documentation and a module-load test, with no runtime API yet.

This package will own native model artifacts, tensor loading, model adapters and Nx.Serving execution. It does not own shared wire/inference contracts, provider-specific hosted HTTP internals, or lifecycle management. Those belong to
SystemOneContracts, TypeSafeAPISDK and external lifecycle tooling respectively.

## Intended installation (after publication)

```elixir
{:system_one_bumblebee, "~> 0.1.0"}
```

For development, run `mix deps.get` and `mix test` from this directory.
The explicit `../system_one_contracts` path dependency is development-only. Replace it with
`{:system_one_contracts, "~> 0.1.0"}` after the contracts package is published; `../../scripts/release_check system_one_bumblebee` refuses path dependencies.

## Next implementation

Laya/ModernBERT, safetensors mapping, tokenizer parity, Python oracle fixtures, CPU and EXLA/GPU parity, resident Nx.Serving, then Qwen option/logit scoring.

Bumblebee, Nx, Axon and EXLA are upcoming dependencies, pending the native dependency audit. No ML stack or model downloads are installed by this scaffold. This will execute real imported tensor weights on BEAM/Nx, not wrap a Python service.

[Contracts](../system_one_contracts/README.md) · [SDK](../system_one_sdk/README.md) · [Bumblebee](../system_one_bumblebee/README.md) · [Server](../system_one_server/README.md) · [Repository](../../README.md)

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
