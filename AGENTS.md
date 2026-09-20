# SystemOneSDK Agent Notes

## Architecture

SystemOneSDK is provider-neutral.

Dependency direction:

    SystemOneSDK
      -> SystemOneSDK.Provider
      -> provider adapter
      -> provider SDK

The built-in TypeSafe path is:

    SystemOneSDK
      -> SystemOneSDK.Providers.TypeSafe
      -> TypeSafeAPISDK
      -> TypeSafe hosted API

`typesafe_api_sdk` owns TypeSafe-specific HTTP, authentication, endpoint
defaults, generated operations, wire schemas, retries, raw HTTP metadata, and
OpenAPI maintenance.

SystemOneSDK owns reusable semantic behavior: Noul, Choice, Score, preparation,
evaluation, response contracts, batching, telemetry, OTP integration, runtime
controls, model helpers, evaluation tooling, and testing helpers.

Do not reintroduce TypeSafe OpenAPI/codegen ownership here.

## Local dependency development

The committed dependency is:

    {:typesafe_api_sdk, "~> 0.1.0"}

For sibling development:

    export MIX_WORKSPACE_OPS_BOOTSTRAP="$PWD/scripts/local_workspace.exs"

## Quality gates

    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test --warnings-as-errors
    mix credo --strict
    mix dialyzer
    mix docs --warnings-as-errors

Package verification must disable local dependency overrides:

    unset MIX_WORKSPACE_OPS_BOOTSTRAP
    unset TYPESAFE_API_SDK_PATH
    mix hex.build --unpack

## Release order

Publish the required `typesafe_api_sdk` version before the SystemOneSDK release
that depends on it.
