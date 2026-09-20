# Publishing

Run commands inside the chosen `packages/<package>` directory. See
[release order](docs/RELEASE_ORDER.md). No package is published by the scripts.

Full SDK gates: `mix deps.get`, `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test --warnings-as-errors`,
`mix credo --strict`, `mix dialyzer`, `mix docs --warnings-as-errors`.

From the root run `scripts/release_check PACKAGE` to reject local dependencies
and build the Hex artifact. Inspect the archive, metadata, LICENSE and docs.
The optional packages intentionally fail this gate until their development-only
sibling dependencies become `{:system_one_sdk, "~> 0.6.0"}` after SDK publication.
Runtime completion and full release review are required beyond this structural gate.
