# Architecture

This package depends on SystemOneSDK; the SDK never depends on this package.
It will own native model artifacts, tensor loading, model adapters and Nx.Serving execution. Shared provider-neutral contracts and conformance
belong in SystemOneSDK. No standalone contracts package is planned.

Next: Laya/ModernBERT, safetensors mapping, tokenizer parity, Python oracle fixtures, CPU and EXLA/GPU parity, resident Nx.Serving, then Qwen option/logit scoring.
