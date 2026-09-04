#!/usr/bin/env bash
set -euo pipefail

# Budgets. Set on 2026-09-04 from the measured distribution of eleven existing
# trackers: the ones that were still status panels had at most 77 words in a
# table cell and at most 10 lines of baseline; the ones that had turned into
# delivery logs carried 234–472-word cells and a 35-line baseline. Change these
# only through /idd-evolve, never per project.
CELL_WORD_BUDGET=80
BASELINE_LINE_BUDGET=20

usage() { echo "usage: tracker-gate.sh PROGRESS.md" >&2; exit 64; }
[ "$#" -eq 1 ] || usage
tracker="$1"
[ -f "$tracker" ] || { echo "FAIL: tracker does not exist: $tracker" >&2; exit 2; }

# Read-only by construction: the gate reports and stops; it never rewrites.
failures="$(awk -v cell_budget="$CELL_WORD_BUDGET" -v baseline_budget="$BASELINE_LINE_BUDGET" '
  /^## / { in_baseline = 0 }
  /^## .*[Bb]aseline/ { in_baseline = 1; next }
  in_baseline { baseline_lines++ }
  /^## [Uu]pdate rule/ { has_update_rule = 1 }
  /^\|/ {
    if ($0 ~ /^\|[-: |]+\|$/) next
    n = split($0, cells, "|")
    for (i = 2; i < n; i++) {
      cell = cells[i]
      gsub(/^[ \t]+|[ \t]+$/, "", cell)
      words = (cell == "") ? 0 : split(cell, tmp, /[ \t]+/)
      excerpt = (length(cell) > 60) ? substr(cell, 1, 60) "..." : cell
      if (words > cell_budget)
        printf "line %d, cell %d: %d words, budget %d: %s\n", NR, i - 1, words, cell_budget, excerpt
      if (cell ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
        printf "line %d, cell %d: carries a date; chronology belongs to Git and GitHub: %s\n", NR, i - 1, excerpt
    }
  }
  END {
    if (baseline_lines > baseline_budget)
      printf "baseline section: %d lines, budget %d\n", baseline_lines, baseline_budget
    if (!has_update_rule)
      print "missing section: ## Update rule"
  }
' "$tracker")"

if [ -n "$failures" ]; then
  printf 'FAIL: tracker gate (%s)\n%s\n' "$tracker" "$failures" >&2
  exit 1
fi
printf 'PASS: tracker gate (%s)\n' "$tracker"
