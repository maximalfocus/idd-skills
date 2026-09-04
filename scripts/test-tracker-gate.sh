#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="${TRACKER_GATE_SCRIPT:-$root/scripts/tracker-gate.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

panel() { # a passing status panel
  cat <<'TRACKER'
# demo implementation progress

## Implemented baseline

- Coverage: R-001–R-003
- Source: `abc123` on `example/demo@main`

## Update rule

- Replace status in place; never append narrative.

## Current implementation

| Slice | Requirement | Status | Missing acceptance | Next action |
|---|---|---|---|---|
| S-004 | R-004 | Ready | CLI journey at the real boundary | `/idd-issue` creates the issue |
TRACKER
}

refuses() { # $1 = description, $2 = tracker file, $3 = required stderr fragment
  local before after err
  before="$(cksum < "$2")"
  if err="$(bash "$gate" "$2" 2>&1 >/dev/null)"; then
    echo "tracker gate accepted $1" >&2; exit 1
  fi
  case "$err" in
    *"$3"*) ;;
    *) echo "tracker gate rejected $1 for the wrong reason: $err" >&2; exit 1;;
  esac
  after="$(cksum < "$2")"
  [ "$before" = "$after" ] || { echo "tracker gate rewrote the tracker while rejecting $1" >&2; exit 1; }
}

panel > "$tmp/pass.md"
bash "$gate" "$tmp/pass.md" | grep -q '^PASS: tracker gate' || { echo "tracker gate rejected a status panel" >&2; exit 1; }

# An over-budget cell is reported by line and cell, then the gate stops.
long="$(awk 'BEGIN { for (i = 0; i < 90; i++) printf "word " }')"
panel | sed "s|CLI journey at the real boundary|$long|" > "$tmp/cell.md"
refuses "an over-budget table cell" "$tmp/cell.md" "line 16, cell 4: 90 words, budget 80"

# A date inside a table cell is chronology, which belongs to Git and GitHub.
panel | sed 's|Ready|Landed 2026-08-21|' > "$tmp/dated.md"
refuses "a dated table cell" "$tmp/dated.md" "line 16, cell 3: carries a date"

# A baseline that grows past its budget has become a delivery log.
{ panel | sed -n '1,6p'; awk 'BEGIN { for (i = 0; i < 20; i++) print "- one more historical bullet" }'; panel | sed -n '7,$p'; } > "$tmp/baseline.md"
refuses "an over-budget baseline" "$tmp/baseline.md" "baseline section: 24 lines, budget 20"

# Every tracker states how it is maintained.
panel | sed '/^## Update rule/,/^$/d' > "$tmp/norule.md"
refuses "a tracker without an update rule" "$tmp/norule.md" "missing section: ## Update rule"

bash "$gate" "$tmp/absent.md" 2>/dev/null && { echo "tracker gate accepted a missing file" >&2; exit 1; }

echo "tracker gate valid"
