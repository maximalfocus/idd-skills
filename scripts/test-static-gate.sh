#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="${STATIC_GATE_SCRIPT:-$root/skills/idd-acceptance/scripts/static-gate.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

refuses() { # $1 = description, $2 = suite, $3 = required stderr fragment
  local err
  if err="$(PATH=/usr/bin:/bin bash "$gate" "$2" 2>&1 >/dev/null)"; then
    echo "static gate accepted $1" >&2; exit 1
  fi
  case "$err" in
    *"$3"*) ;;
    *) echo "static gate rejected $1 for the wrong reason: $err" >&2; exit 1;;
  esac
}

# Every run uses a minimal PATH so an optional tool such as ripgrep can never
# be what makes the gate pass or fail.
mkdir -p "$tmp/wait" "$tmp/class" "$tmp/ok"
printf "test('x', async ({ page }) => {\n  await page.waitForTimeout(500);\n});\n" > "$tmp/wait/a.spec.ts"
printf "test('x', async ({ page }) => {\n  await page.locator('.btn-primary').click();\n});\n" > "$tmp/class/a.spec.js"
printf "test('x', async ({ page }) => {\n  await page.getByRole('button', { name: 'Save' }).click();\n});\n" > "$tmp/ok/a.spec.tsx"

refuses "a fixed wait" "$tmp/wait" "fixed browser wait found"
refuses "a class-based locator" "$tmp/class" "brittle class-based locator found"
PATH=/usr/bin:/bin bash "$gate" "$tmp/ok" | grep -q '^PASS: acceptance static gate' || { echo "static gate rejected a semantic suite" >&2; exit 1; }
PATH=/usr/bin:/bin bash "$gate" "$tmp/absent" 2>/dev/null && { echo "static gate accepted a missing suite" >&2; exit 1; }

echo "acceptance static gate valid"
