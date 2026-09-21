#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/qc"
"$root/scripts/release_qc.sh" offline
"$root/scripts/release_check" system_one_contracts
