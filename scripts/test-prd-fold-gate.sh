#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="${PRD_FOLD_GATE_SCRIPT:-$root/scripts/prd-fold-gate.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/PROGRESS.md" <<'TRACKER'
# progress

## Implemented baseline

- Delivered slices: S-004–S-005

## Update rule

- Replace in place.

## Current implementation

| Slice | Requirement | Status | Evidence |
|---|---|---|---|
| S-001 | R-001 | Validated | #1 / PR #2 |
| S-002 | R-002 | Ready | none |
| S-003 | R-003 | Validated | #3 / PR #4 |
TRACKER

prd() { # $@ = extra sections
  { printf '# demo\n\n## Requirements\n\n### R-001 — One\n\nAcceptance.\n\n## Delivery slices\n\n| Slice | Requirement | Status |\n|---|---|---|\n| S-003 | R-003 | Validated |\n\n'; printf '%s\n' "$@"; } > "$tmp/PRD.md"
}

# A validated slice that still owns a section is reported with its size and line.
prd '### S-001 — Delivered thing' '' 'Line one.' 'Line two.' '' '### S-002 — Ready thing' '' 'Keeps its section while ready.' ''
if err="$(bash "$gate" "$tmp/PRD.md" "$tmp/PROGRESS.md" 2>&1 >/dev/null)"; then echo "fold gate accepted an unfolded validated slice" >&2; exit 1; fi
case "$err" in *"UNFOLDED: S-001 is validated but still owns a 5-line section at $tmp/PRD.md:15"*) ;; *) echo "wrong report: $err" >&2; exit 1;; esac
case "$err" in *"S-002"*) echo "fold gate reported a ready slice" >&2; exit 1;; esac

# Ids inside a baseline range count as validated too.
prd '### S-002 — Ready thing' '' 'Kept.' '' '#### S-005 — Folded into the baseline but still here' '' 'Stale.' ''
if err="$(bash "$gate" "$tmp/PRD.md" "$tmp/PROGRESS.md" 2>&1 >/dev/null)"; then echo "fold gate accepted a baseline slice with a section" >&2; exit 1; fi
case "$err" in *"UNFOLDED: S-005 is validated"*) ;; *) echo "wrong report for a baseline range: $err" >&2; exit 1;; esac

# Folded: validated slices appear only as table rows.
prd '### S-002 — Ready thing' '' 'Kept.' ''
bash "$gate" "$tmp/PRD.md" "$tmp/PROGRESS.md" | grep -q '^PASS: prd fold gate' || { echo "fold gate rejected a folded PRD" >&2; exit 1; }
[ "$(cksum < "$tmp/PRD.md")" = "$(cksum < "$tmp/PRD.md")" ]

bash "$gate" "$tmp/absent.md" "$tmp/PROGRESS.md" 2>/dev/null && { echo "fold gate accepted a missing PRD" >&2; exit 1; }
echo "prd fold gate valid"
