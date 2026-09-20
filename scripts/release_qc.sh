#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/packages/system_one_sdk"
case "${1:-offline}" in
  offline)
    mix deps.get
    mix format --check-formatted
    mix compile --warnings-as-errors
    mix test --warnings-as-errors
    mix credo --strict
    mix dialyzer
    mix docs --warnings-as-errors
    ;;
  package-dry-run) exec "$root/scripts/release_check" system_one_sdk ;;
  live)
    : "${TYPESAFE_API_KEY:?TYPESAFE_API_KEY is required for live QC}"
    mix deps.get
    mix test --include live
    ;;
  *) echo "usage: $0 {offline|package-dry-run|live}" >&2; exit 64 ;;
esac
