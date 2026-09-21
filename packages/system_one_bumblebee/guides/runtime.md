# Runtime

`SystemOneBumblebee.Provider.new/1` constructs provider state from an explicit model registry and `SystemOneBumblebee.RuntimeProfile`.

The application supervisor starts a unique Registry and DynamicSupervisor. The first request for a model starts `SystemOneBumblebee.Serving`, which:

1. verifies/downloads the model's immutable artifact pin;
2. invokes the configured `ModelAdapter.load/4` once;
3. keeps the returned runtime resident;
4. exposes immutable runtime snapshots to concurrent inference callers.

Inference emits a `[:system_one_bumblebee, :inference, ...]` telemetry span with model, adapter and runtime-profile metadata.

## Runtime profiles

Profiles carry execution choices explicitly:

```elixir
profile =
  SystemOneBumblebee.RuntimeProfile.new!(
    name: :cuda,
    backend: MyNxBackend,
    compiler: MyNxCompiler,
    type: :bf16,
    batch_size: 1,
    sequence_length: 512
  )
```

The package does not require EXLA. A host with EXLA installed may pass EXLA backend/compiler terms in the profile used by its model adapter.

`RuntimeProfile.test/0` is intended for deterministic fake-adapter CI. `RuntimeProfile.cpu/0` selects `Nx.BinaryBackend` and FP32.
