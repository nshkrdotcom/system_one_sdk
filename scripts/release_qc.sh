#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mode="${1:-offline}"

use_local_provider() {
  export MIX_WORKSPACE_OPS_BOOTSTRAP="$PWD/scripts/local_workspace.exs"
}

case "$mode" in
  offline)
    use_local_provider
    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test --warnings-as-errors
    mix credo --strict
    mix dialyzer
    mix docs --warnings-as-errors
    ;;

  package-dry-run)
    unset MIX_WORKSPACE_OPS_BOOTSTRAP || true
    unset TYPESAFE_API_SDK_PATH || true
    rm -rf system_one_sdk-0.5.0
    mix hex.build --unpack
    ;;

  live)
    if [[ -z "${TYPESAFE_API_KEY:-}" ]]; then
      echo "TYPESAFE_API_KEY is required for live QC." >&2
      exit 1
    fi

    use_local_provider
    mix deps.get
    mix test --include live
    ;;

  *)
    echo "usage: $0 {offline|package-dry-run|live}" >&2
    exit 64
    ;;
esac
