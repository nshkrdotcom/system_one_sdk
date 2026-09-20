# Verification

From the root run `scripts/qc`: dependencies, formatting, test compilation and
offline tests for every package. Each package's docs build independently with
`mix docs --warnings-as-errors` from that package directory.

`scripts/release_qc.sh offline` retains full SDK checks including Credo and
Dialyzer. `scripts/release_check system_one_sdk` validates published dependency
composition and builds the Hex artifact. No bootstrap or sibling provider override.

Live tests remain manual and opt-in: `scripts/release_qc.sh live` requires
TYPESAFE_API_KEY and runs `mix test --include live`. Do not run for routine QC.
The SDK does not own a second TypeSafe OpenAPI/codegen verification pipeline.
