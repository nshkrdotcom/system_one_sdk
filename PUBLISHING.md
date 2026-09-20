# Publishing SystemOneSDK

## Release order

`system_one_sdk 0.5.0` depends on:

    {:typesafe_api_sdk, "~> 0.1.0"}

Publish `typesafe_api_sdk 0.1.0` before publishing SystemOneSDK 0.5.0.

## Local development

Use the sibling provider checkout without changing committed package metadata:

    export MIX_WORKSPACE_OPS_BOOTSTRAP="$PWD/scripts/local_workspace.exs"
    mix deps.get
    mix test

## Pre-release gates

    export MIX_WORKSPACE_OPS_BOOTSTRAP="$PWD/scripts/local_workspace.exs"

    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test --warnings-as-errors
    mix credo --strict
    mix dialyzer
    mix docs --warnings-as-errors

Optional real-provider verification:

    export TYPESAFE_API_KEY='...'
    mix test --include live

## Package gate

Disable all local dependency overrides:

    unset MIX_WORKSPACE_OPS_BOOTSTRAP
    unset TYPESAFE_API_SDK_PATH

    rm -rf system_one_sdk-0.5.0
    mix hex.build --unpack

`typesafe_api_sdk` must appear as a normal Hex requirement.

After `typesafe_api_sdk 0.1.0` is available on Hex and all release gates pass:

    mix hex.publish
