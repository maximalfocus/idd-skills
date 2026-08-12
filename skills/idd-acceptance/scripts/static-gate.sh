#!/usr/bin/env bash
set -euo pipefail

suite="${1:?usage: static-gate.sh <browser-suite-directory>}"
[[ -d "$suite" ]] || { printf 'FAIL: suite directory does not exist: %s\n' "$suite" >&2; exit 2; }

if rg -n --glob '*.js' --glob '*.jsx' --glob '*.ts' --glob '*.tsx' 'waitForTimeout[[:space:]]*\(' "$suite"; then
  printf 'FAIL: fixed browser wait found; wait for observable state instead.\n' >&2
  exit 1
fi

if rg -n --glob '*.js' --glob '*.jsx' --glob '*.ts' --glob '*.tsx' "locator\\([[:space:]]*[\"'][^\"']*\\.[A-Za-z_-]" "$suite"; then
  printf 'FAIL: brittle class-based locator found; use semantic selectors.\n' >&2
  exit 1
fi

printf 'PASS: acceptance static gate (%s)\n' "$suite"
