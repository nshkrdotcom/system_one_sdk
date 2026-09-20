# Changelog

All notable changes to SystemOneSDK are documented here.

The project follows Semantic Versioning.

## [0.5.0] - 2026-09-19

### Added

- Established `system_one_sdk` as the provider-neutral Elixir/BEAM SDK for
  System One semantic evaluation.
- Added the `SystemOneSDK.Provider` contract.
- Added `SystemOneSDK.Providers.TypeSafe` as the first built-in provider.
- Added `typesafe_api_sdk ~> 0.1.0` as the TypeSafe provider dependency.
- Preserved Noul, Choice, Score, prepared evaluation, response contracts,
  batching, telemetry, runtime controls, OTP integration, model helpers,
  evaluation tooling, and testing helpers.
- Added local workspace dependency selection for sibling provider development.

### Changed

- Moved TypeSafe HTTP, authentication, OpenAPI operations, generated wire
  schemas, endpoint defaults, and provider transport ownership into
  `typesafe_api_sdk`.
- Routed semantic evaluation through the provider contract.
- Normalized provider errors at the SystemOneSDK boundary while preserving
  direct Pristine cancellation causes.
- Converted `typesafe_api_sdk` from a committed path dependency to a normal Hex
  requirement, with local checkout selection handled only by development
  workspace configuration.

### Removed

- Removed the copied TypeSafe OpenAPI snapshot.
- Removed the generated TypeSafe wire client and schema modules.
- Removed TypeSafe provider-codegen and schema maintenance Mix tasks.
- Removed committed TypeSafe JSON Schema exports.
- Removed old TypeSafeSDK migration, implementation-plan, and handoff material.
