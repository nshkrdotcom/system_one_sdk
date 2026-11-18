<p align="center">
  <img src="assets/system_one_ecosystem.svg" width="200" height="200" alt="System One ecosystem"/>
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/system_one_sdk/actions/workflows/ci.yml"><img src="https://github.com/nshkrdotcom/system_one_sdk/actions/workflows/ci.yml/badge.svg" alt="CI"/></a>
  <a href="https://hex.pm/packages/system_one_sdk"><img src="https://img.shields.io/hexpm/v/system_one_sdk.svg?color=6E4A7E&label=system_one_sdk" alt="Hex.pm"/></a>
  <a href="https://hexdocs.pm/system_one_sdk"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="HexDocs"/></a>
  <img src="https://img.shields.io/badge/elixir-~%3E%201.18-4B275F?logo=elixir&logoColor=white" alt="Elixir ~> 1.18"/>
  <img src="https://img.shields.io/badge/OTP-28%2B-A90533?logo=erlang&logoColor=white" alt="OTP 28+"/>
  <img src="https://img.shields.io/badge/protocol-system--one%2Fv1-0F766E" alt="system-one/v1"/>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="MIT License"/></a>
</p>

# System One SDK Poncho

Four independently publishable Mix projects. This repository is a Poncho, not
an Elixir umbrella: each package owns its dependencies, lockfile and build.
The root provides documentation and orchestration only.

| Package | Purpose | Typical user |
| --- | --- | --- |
| [system_one_contracts](packages/system_one_contracts) | Small provider-neutral System One v1 wire/inference contract package | Runtime/server implementers |
| [system_one_sdk](packages/system_one_sdk) | Rich provider-neutral System One API and default hosted TypeSafe integration | Nearly everyone |
| [system_one_bumblebee](packages/system_one_bumblebee) | Optional native BEAM/Nx model execution (upcoming) | Self-hosted/native inference users |
| [system_one_server](packages/system_one_server) | Optional HTTP service exposing System One v1 (upcoming) | Remote/service deployments |

Most application users need only:

```elixir
{:system_one_sdk, "~> 0.6"}
```

Runtime/server implementers may depend directly on the smaller
`system_one_contracts` package. The release versions are SystemOneSDK 0.6.0 and
SystemOneContracts 0.1.0. TypeSafeAPISDK remains a published Hex dependency.

SystemOneSDK itself is programmatic. The server is optional. Native inference is
optional. Hosted use does not require Bumblebee, Nx, EXLA, Plug or Bandit. The
provider-specific `typesafe_api_sdk` remains an ordinary Hex dependency of the
main SDK.

## Development

```bash
./scripts/qc
cd packages/system_one_sdk
mix docs --warnings-as-errors
```

Fast QC fetches dependencies and runs formatting, test compilation and offline
tests per package. It does not run live calls, Dialyzer or model downloads.
The SDK uses `system_one_contracts ~> 0.1.0` from Hex. Bumblebee and Server
currently use sibling contracts paths for development; their release gates
require switching those dependencies to Hex.

See [architecture](docs/ARCHITECTURE.md), [packages](docs/PACKAGES.md),
[roadmap](docs/ROADMAP.md), [release order](docs/RELEASE_ORDER.md),
[verification](VERIFICATION.md) and [publishing](PUBLISHING.md).

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
