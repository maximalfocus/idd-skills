#!/usr/bin/env bash
set -euo pipefail

suite="${1:?usage: static-gate.sh <browser-suite-directory>}"
[[ -d "$suite" ]] || { printf 'FAIL: suite directory does not exist: %s\n' "$suite" >&2; exit 2; }

# grep, never ripgrep: a tool that is absent must not turn this gate green.
scan() { grep -rEn --include='*.js' --include='*.jsx' --include='*.ts' --include='*.tsx' -e "$1" "$suite"; }

if scan 'waitForTimeout[[:space:]]*\('; then
  printf 'FAIL: fixed browser wait found; wait for observable state instead.\n' >&2
  exit 1
fi

if scan "locator\\([[:space:]]*[\"'][^\"']*\\.[A-Za-z_-]"; then
  printf 'FAIL: brittle class-based locator found; use semantic selectors.\n' >&2
  exit 1
fi

printf 'PASS: acceptance static gate (%s)\n' "$suite"
