#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec bash "$root/skills/idd-plan/scripts/resolve-prd-pair.sh" "$@"
