<img src="assets/system_one_ecosystem.svg" width="200" height="200" alt="System One ecosystem">

# System One SDK Poncho

Three independently publishable Mix projects. This repository is a Poncho, not
an Elixir umbrella: each package owns its dependencies, lockfile and build.
The root provides documentation and orchestration only.

| Package | Purpose | Typical user |
| --- | --- | --- |
| [system_one_sdk](packages/system_one_sdk) | Provider-neutral System One API and default hosted TypeSafe integration | Nearly everyone |
| [system_one_bumblebee](packages/system_one_bumblebee) | Optional native BEAM/Nx model execution (upcoming) | Self-hosted/native inference users |
| [system_one_server](packages/system_one_server) | Optional HTTP service exposing System One v1 (upcoming) | Remote/service deployments |

Most users need only:

```elixir
{:system_one_sdk, "~> 0.6"}
```

This is the upcoming release line. **0.5.0 is published; 0.6.0 is under development.**
Both optional packages are unpublished 0.1.0 scaffolds.

SystemOneSDK itself is programmatic. The server is optional. Native inference is
optional. Hosted use does not require Bumblebee, Nx, EXLA, Plug or Bandit.
The separate provider-specific `typesafe_api_sdk 0.1.0` is already published and
is an ordinary Hex dependency of the main SDK.

## Development

```bash
./scripts/qc
cd packages/system_one_sdk
mix docs --warnings-as-errors
```

Fast QC fetches dependencies and runs formatting, test compilation and offline
tests per package. It does not run live calls, Dialyzer or model downloads.
The two new packages explicitly depend on the sibling SDK for development;
replace that path with `{:system_one_sdk, "~> 0.6.0"}` after SDK publication.
`./scripts/release_check PACKAGE` rejects path/Git dependencies before building.

See [architecture](docs/ARCHITECTURE.md), [packages](docs/PACKAGES.md),
[roadmap](docs/ROADMAP.md), [release order](docs/RELEASE_ORDER.md),
[verification](VERIFICATION.md) and [publishing](PUBLISHING.md).

[MIT License](LICENSE) — Copyright (c) 2026 nshkrdotcom
