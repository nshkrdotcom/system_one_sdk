# Architecture

This package depends only on `system_one_contracts` at the System One boundary;
it does not depend on the rich `system_one_sdk` package. It will implement
`SystemOneContracts.Provider` and own native model artifacts, tensor loading,
model adapters and Nx.Serving execution.

Applications that want the rich SDK can bridge this provider through
`SystemOneSDK.Providers.Contract`, but that dependency points from the
application/SDK side toward the provider rather than back into this package.

Next: Laya/ModernBERT, safetensors mapping, tokenizer parity, Python oracle
fixtures, CPU and EXLA/GPU parity, resident Nx.Serving, then Qwen option/logit
scoring.
