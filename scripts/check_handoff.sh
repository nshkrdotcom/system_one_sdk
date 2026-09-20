#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export MIX_WORKSPACE_OPS_BOOTSTRAP="$PWD/scripts/local_workspace.exs"

mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix credo --strict
mix dialyzer
mix docs --warnings-as-errors

unset MIX_WORKSPACE_OPS_BOOTSTRAP
unset TYPESAFE_API_SDK_PATH

rm -rf system_one_sdk-0.5.0
mix hex.build --unpack
