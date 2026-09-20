# System One Poncho agent notes

This is not an umbrella. Run Mix inside `packages/<package>`; root `scripts/qc`
runs fast checks across all three independent projects.

SystemOneSDK → SystemOneSDK.Provider → provider adapter → provider SDK.
TypeSafeAPISDK owns TypeSafe HTTP/auth/defaults/generated operations/wire schemas,
retries/raw metadata/OpenAPI maintenance. Do not reintroduce codegen here.
SystemOneSDK owns reusable semantics, preparation, evaluation, batching, telemetry,
OTP/runtime controls, model helpers and testing, including upcoming v1 conformance.

Main SDK uses published typesafe_api_sdk ~> 0.1.0 without bootstrap overrides.
Optional packages use explicit development-only sibling paths; before releasing,
replace with system_one_sdk ~> 0.6.0. SDK must never depend on optional packages.

Fast gates: mix deps.get; mix format --check-formatted;
MIX_ENV=test mix compile --warnings-as-errors; mix test --warnings-as-errors.
Docs: mix docs --warnings-as-errors. Main SDK full gates additionally include
mix credo --strict and mix dialyzer. Never include live tests by default.
Use scripts/release_check PACKAGE for manifest/build verification.
See docs/ROADMAP.md and docs/RELEASE_ORDER.md. No standalone contracts package.
