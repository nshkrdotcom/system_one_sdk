# Publishing

Run commands inside the chosen `packages/<package>` directory. See
[release order](docs/RELEASE_ORDER.md). No package is published by the scripts.

Full SDK gates: `mix deps.get`, `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test --warnings-as-errors`,
`mix credo --strict`, `mix dialyzer`, `mix docs --warnings-as-errors`.

From the root run `scripts/release_check PACKAGE` to reject local dependencies
and build the Hex artifact. Inspect the archive, metadata, LICENSE and docs.
Publish `system_one_contracts` first. Dependent packages intentionally fail the
release gate while they still reference the sibling contracts path; replace it
with `{:system_one_contracts, "~> 0.1.0"}` before their release. Runtime
completion and full release review are required beyond this structural gate.
