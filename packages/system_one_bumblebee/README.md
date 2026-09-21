<img src="assets/system_one_bumblebee.svg" width="200" height="200" alt="SystemOneBumblebee">

# SystemOneBumblebee

Native BEAM/Nx/Bumblebee implementation of System One inference.

**0.1.0 is unpublished and under active development.** The provider/runtime core is now implemented; Laya model parity is the next gate.

SystemOneBumblebee implements the inference-side `SystemOneContracts.Provider` boundary. It owns explicit model registration, immutable Hugging Face artifact pins, SHA-256 and SafeTensors manifest verification, model adapter loading, runtime profiles and long-lived resident model state. It does **not** own HTTP exposure, hosted credentials or service lifecycle management.

## Native dependency graph

The current coherent released stack is:

```text
system_one_contracts
nx 0.13.x
axon 0.8.x
bumblebee 0.7.x
hf_hub 0.4.x development source
crucible_safetensors 0.2.x development source
jason
telemetry
```

EXLA is intentionally **not** a required production dependency. The embedding application supplies backend/compiler choices through `SystemOneBumblebee.RuntimeProfile`.

## Provider core

```elixir
alias SystemOneBumblebee.{Adapters.Fake, Provider, RuntimeProfile}

{:ok, provider_state} =
  Provider.new(
    models: %{
      "fixture" => %{
        adapter: Fake,
        aliases: ["fixture-alias"]
      }
    },
    runtime_profile: RuntimeProfile.test()
  )

{:ok, catalog} = Provider.list_models(provider_state, [])
```

`SystemOneBumblebee.Adapters.Fake` exists only for deterministic offline contract tests. Production models use architecture-specific adapters.

## Artifact identity

Production model manifests use `SystemOneBumblebee.ArtifactPin`:

- full 40-character Hugging Face commit revision;
- SHA-256 for every required file;
- optional exact SafeTensors tensor inventory;
- no request-driven arbitrary repository selection.

`HfHub.Download` owns download/cache mechanics. `CrucibleSafetensors` independently verifies hashes and checkpoint metadata before an adapter allocates tensors.

## Development dependencies

The repository currently uses local path dependencies for the unpublished `system_one_contracts`, `hf_hub` 0.4 and `crucible_safetensors` 0.2 development sources. `scripts/release_check system_one_bumblebee` intentionally refuses path dependencies. Replace them with Hex requirements only after those prepared releases are published.

## Next implementation

Laya is next: pin the exact upstream/model commits, record every file SHA-256, stage Python oracle fixtures, reproduce preprocessing, load ModernBERT through Bumblebee, implement the Laya-specific decision head/scorer/action path, account for every checkpoint tensor, then gate CPU parity before GPU parity.

[Contracts](../system_one_contracts/README.md) · [SDK](../system_one_sdk/README.md) · [Bumblebee](../system_one_bumblebee/README.md) · [Server](../system_one_server/README.md) · [Repository](../../README.md)

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
