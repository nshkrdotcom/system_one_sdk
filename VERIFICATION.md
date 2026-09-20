# Verification

SystemOneSDK has two verification modes.

## Offline acceptance

When developing beside `typesafe_api_sdk`:

    export MIX_WORKSPACE_OPS_BOOTSTRAP="$PWD/scripts/local_workspace.exs"

    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test --warnings-as-errors
    mix credo --strict
    mix dialyzer
    mix docs --warnings-as-errors

The TypeSafe provider is exercised through the public `TypeSafeAPISDK` package
boundary. SystemOneSDK does not maintain a second OpenAPI/codegen verification
pipeline.

## Package verification

Hex metadata must be checked with local dependency overrides disabled:

    unset MIX_WORKSPACE_OPS_BOOTSTRAP
    unset TYPESAFE_API_SDK_PATH

    mix hex.build --unpack

The resulting package must contain a normal Hex requirement for
`typesafe_api_sdk ~> 0.1.0`, not a path or Git dependency.

## Live verification

Live tests are opt-in:

    export TYPESAFE_API_KEY='...'
    mix test --include live

Provider-specific credentials, endpoint configuration, and model identifiers
belong to the selected provider adapter. The built-in TypeSafe adapter uses the
configuration supported by `TypeSafeAPISDK`.
