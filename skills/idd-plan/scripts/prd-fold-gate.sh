#!/usr/bin/env bash
set -euo pipefail

# A slice owns a PRD section only while it is ready or active. Once it is
# validated, its acceptance belongs to the requirement it extends and the
# slice collapses to one row; a validated slice that still owns a section is
# reported here. Read-only: it names the section and stops.
usage() { echo "usage: prd-fold-gate.sh PRD.md PROGRESS.md" >&2; exit 64; }
[ "$#" -eq 2 ] || usage
prd="$1"; tracker="$2"
[ -f "$prd" ] || { echo "FAIL: PRD does not exist: $prd" >&2; exit 2; }
[ -f "$tracker" ] || { echo "FAIL: tracker does not exist: $tracker" >&2; exit 2; }

# Validated slice ids: any id on a table row that says validated, and any id
# or id range inside the tracker's baseline section, which is folded by
# definition. Ranges read S-001–S-004, S-001..S-004, or S-001 through S-004.
validated="$(awk '
  /^## / { in_baseline = ($0 ~ /[Bb]aseline/) }
  in_baseline || (/^\|/ && tolower($0) ~ /validated/) { print }
' "$tracker" | awk '
  {
    line = $0
    while (match(line, /(S|SLICE)-[0-9]+[[:space:]]*(–|—|\.\.|-|through|to)[[:space:]]*(S|SLICE)-[0-9]+/)) {
      range = substr(line, RSTART, RLENGTH)
      n = split(range, parts, /[^0-9]+/)
      lo = ""; hi = ""
      for (i = 1; i <= n; i++) if (parts[i] != "") { if (lo == "") lo = parts[i]; else hi = parts[i] }
      prefix = (range ~ /^SLICE/) ? "SLICE" : "S"
      width = length(lo)
      for (k = lo + 0; k <= hi + 0; k++) printf "%s-%0*d\n", prefix, width, k
      line = substr(line, RSTART + RLENGTH)
    }
    line = $0
    while (match(line, /(S|SLICE)-[0-9]+/)) { print substr(line, RSTART, RLENGTH); line = substr(line, RSTART + RLENGTH) }
  }
' | sort -u)"

failures=""
while IFS= read -r id; do
  [ -n "$id" ] || continue
  found="$(awk -v id="$id" '
    /^#+ / {
      level = index($0, " ") - 1
      if (open && level <= open_level) { printf "%s\t%d\t%d\n", id, start, NR - start; open = 0 }
      if (!open && $0 ~ ("(^|[^A-Za-z0-9-])" id "([^0-9]|$)")) { open = 1; open_level = level; start = NR }
    }
    END { if (open) printf "%s\t%d\t%d\n", id, start, NR - start + 1 }
  ' "$prd")"
  [ -n "$found" ] || continue
  while IFS=$'\t' read -r sid line lines; do
    failures="${failures}UNFOLDED: $sid is validated but still owns a ${lines}-line section at $prd:$line
"
  done <<<"$found"
done <<<"$validated"

if [ -n "$failures" ]; then
  printf '%s' "$failures" >&2
  echo "FAIL: prd fold gate ($prd): move each section's acceptance into the requirement it extends and collapse the slice to one row (a prd commit)" >&2
  exit 1
fi
printf 'PASS: prd fold gate (%s)\n' "$prd"
