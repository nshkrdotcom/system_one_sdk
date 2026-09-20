#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
"$root/scripts/release_qc.sh" offline
"$root/scripts/release_check" system_one_sdk
