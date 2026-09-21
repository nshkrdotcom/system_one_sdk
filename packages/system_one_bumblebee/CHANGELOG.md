# Changelog

## 0.1.0 — Unreleased

- Add the pinned Laya 0.3.3 source identity, Apache-2.0 third-party notice, staged checkpoint intake, SafeTensors inventory, exact question rendering, qtype mapping, calibration formulas and System One output translation.

- Establish independent package metadata, documentation and compile smoke coverage.
- Depend on the small `system_one_contracts` seam rather than the rich client SDK.
- Add the coherent released native graph: Nx 0.13, Axon 0.8 and Bumblebee 0.7.
- Integrate dependency-prework sources for `hf_hub` 0.4 and `crucible_safetensors` 0.2 during development.
- Add immutable model artifact pins with full Hugging Face commit revisions and per-file SHA-256 digests.
- Add optional SafeTensors header-manifest validation before adapter allocation.
- Add model manifests, explicit registry/alias resolution and runtime profiles.
- Add model-adapter behaviour, resident serving supervision and provider telemetry spans.
- Implement `SystemOneContracts.Provider` for native inference.
- Add deterministic fake adapter and offline provider/conformance tests.
- Keep EXLA host-selected rather than a required package dependency.
- Laya/ModernBERT model parity remains the next release gate.
