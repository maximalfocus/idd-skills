#!/usr/bin/env bash
set -euo pipefail

# Budgets. Set on 2026-09-09 from the wc -w distribution of four existing
# product contracts: the three that were still coherent ran 4,725–7,876 words
# with no single section over 898 words; the one carrying four validated but
# unfolded slices ran 12,319 words with a 1,494-word section. Change these only
# through /idd-evolve, never per project.
SECTION_WORD_BUDGET=1000
TOTAL_WORD_BUDGET=10000

usage() { echo "usage: prd-size-gate.sh PRD.md" >&2; exit 64; }
[ "$#" -eq 1 ] || usage
prd="$1"
[ -f "$prd" ] || { echo "FAIL: PRD does not exist: $prd" >&2; exit 2; }

# A section is a heading line through the line before the next heading of any
# level; only body words count, the heading line itself does not. Text before
# the first heading belongs to no section and counts only toward the total.
# Read-only by construction: the gate reports and stops; it never rewrites.
failures="$(awk -v section_budget="$SECTION_WORD_BUDGET" -v total_budget="$TOTAL_WORD_BUDGET" '
  function flush() {
    if (in_section && words > section_budget)
      printf "line %d: section '"'"'%s'"'"' %d words, budget %d\n", start, heading, words, section_budget
  }
  /^#+ / {
    flush()
    heading = $0; sub(/^#+[ \t]+/, "", heading); sub(/[ \t]+$/, "", heading)
    start = NR; words = 0; in_section = 1
    next
  }
  { total += NF; if (in_section) words += NF }
  END {
    flush()
    if (total > total_budget)
      printf "contract: %d words, budget %d\n", total, total_budget
  }
' "$prd")"

if [ -n "$failures" ]; then
  printf '%s\n' "$failures" >&2
  echo "FAIL: prd size gate ($prd): fold validated slices into their requirements, compress, or narrow the domain boundary and state the remainder as a non-goal (a prd commit)" >&2
  exit 1
fi
printf 'PASS: prd size gate (%s)\n' "$prd"
