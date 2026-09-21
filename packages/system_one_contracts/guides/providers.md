# Inference providers

`SystemOneContracts.Provider` is the inference-side contract. It is intentionally
different from a client/transport provider: the request has already crossed any
HTTP/auth/retry boundary and is represented as a validated protocol DTO.

A provider implements:

- `id/0`
- `capabilities/1`
- `system_one/3`
- `list_models/2`

Provider construction and lifecycle are package-specific. The provider state is
opaque to this package, allowing an in-process Nx.Serving, an attached service,
or another implementation to satisfy the same contract without introducing a
common process manager here.

Use `SystemOneContracts.Conformance.run/3` as a reusable shape/protocol gate. It
checks model discovery, executes a request covering Noul, ordered Choice and
Score, and validates the response against the request without asserting a
particular semantic answer.
