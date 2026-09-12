#!/usr/bin/env bash
set -euo pipefail

# Refuse any line a change adds to a tracked text file beyond 100 characters, the one
# width every IDD-managed repository shares (idd-plan/references/conventions.md). A path
# listed on the repository's `Formatter-owned:` line in AGENTS.md or CLAUDE.md is left to
# the tool that lays it out: a language formatter at its configured width, or a generator,
# package manager, or recorder. A Markdown table row is one line that cannot be rewrapped,
# so its cells answer to their own budgets (the tracker gate's) instead of this width.
#
#   line-width.sh check BASE [REV]      lines REV (default HEAD) adds since its merge base
#   line-width.sh check BASE --cached   lines the index adds to BASE
#   line-width.sh check --root [REV]    every line of REV's tracked text files
#
# Characters are counted, not bytes. Only added lines count, so a change never inherits
# the debt of lines it leaves alone, and a pure rename adds none.
usage() { echo "usage: line-width.sh check BASE|--root [REV|--cached]" >&2; exit 64; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] && [ "$1" = check ] || usage
base="$2"; rev="${3:-HEAD}"
limit=100
[ "$base:$rev" != --root:--cached ] || usage
top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Not in a git repository" >&2; exit 1; }
cd "$top"

declared() { # $1 = conventions file as the checked side holds it; prints its owned paths
  local text
  if [ "$rev" = --cached ]; then text="$(git show ":$1" 2>/dev/null || true)"
  else text="$(git show "$rev:$1" 2>/dev/null || true)"; fi
  printf '%s\n' "$text" | awk '
    /^[[:space:]]*Formatter-owned:/ {
      on = 1; sub(/^[[:space:]]*Formatter-owned:/, ""); print; next }
    on && /^[[:space:]]*(`[^`]+`[[:space:]]*)+$/ { print; next }
    { on = 0 }' | tr -d '`'
}
set -f # owned paths are pathspec patterns, never shell globs
excludes=()
for conventions in AGENTS.md CLAUDE.md; do
  for owned in $(declared "$conventions"); do excludes+=(":(exclude)$owned"); done
done
set +f

empty_tree="$(git hash-object -t tree /dev/null)"
if [ "$rev" = --cached ]; then
  range=(--cached "$base")
elif [ "$base" = --root ]; then
  range=("$empty_tree" "$rev")
else
  merge_base="$(git merge-base "$base" "$rev")" || {
    echo "No merge base between $base and $rev" >&2; exit 1; }
  range=("$merge_base" "$rev")
fi

# One record per added line: "path:line<TAB>content". Headers only precede a file's first
# hunk, and every hunk line carries a +, -, or \ prefix, so content never reads as a header.
records="$(git -c core.quotePath=false diff --no-color --no-ext-diff --no-textconv -U0 \
  --find-renames --src-prefix=a/ --dst-prefix=b/ "${range[@]}" \
  -- . ${excludes[@]+"${excludes[@]}"} |
  awk '
    /^diff --git / { hunk = 0; next }
    hunk && /^\+/ { printf "%s:%d\t%s\n", path, line, substr($0, 2); line++; next }
    !hunk && /^\+\+\+ / { path = substr($0, 5); sub(/^b\//, "", path); next }
    /^@@ / { hunk = 1; split($3, start, ","); line = substr(start[1], 2) + 0; next }' |
  awk -F '\t' '{ # drop Markdown table rows; a pipe line in code is still a line to wrap
    loc = $1; path = loc; sub(/:[0-9]+$/, "", path)
    if (path ~ /\.(md|markdown)$/ && substr($0, length(loc) + 2) ~ /^[ \t]*\|/) next
    print }')"
over=$'\t'".{$((limit + 1)),}\$" # the record's tab, then more than $limit characters of content
wide="$(printf '%s\n' "$records" | LC_ALL=en_US.UTF-8 grep -E "$over" | cut -f1 || true)"
if [ -n "$wide" ]; then
  printf '%s\n' "$wide" | sed "s/^/over $limit characters: /" >&2
  echo "Rewrap each line to $limit characters, or list its path on the repository's" \
    "Formatter-owned: line only when a formatter, generator, package manager, or recorder" \
    "lays it out (idd-plan/references/conventions.md)" >&2
  exit 1
fi
echo "PASS: no added line over $limit characters"
