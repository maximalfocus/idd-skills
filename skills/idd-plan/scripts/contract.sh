#!/usr/bin/env bash
set -euo pipefail

# A contract repository is single-context (root PRD.md and PROGRESS.md only)
# or multi-context: the root PRD.md indexes contexts in a `## Contexts` table
# and each `contexts/<name>/` holds that context's own PRD.md and PROGRESS.md.
# Read-only by construction: every subcommand reports and stops.
usage() {
  cat >&2 <<'USAGE'
usage: contract.sh list CONTRACT_PATH            (context names, one per line)
       contract.sh gate CONTRACT_PATH            (sibling gates on every pair, then structure)
       contract.sh owner CONTRACT_PATH PATH...   (which context's Scope owns each path)
USAGE
  exit 64
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name_re='^[a-z0-9]+(-[a-z0-9]+)*$'

require_contract() {
  [ -d "$1" ] || { echo "FAIL: contract does not exist: $1" >&2; exit 2; }
}

# Prints the sorted context names; a directory under contexts/ holding only
# one of the two files, or carrying a name outside the convention, fails.
contexts_of() {
  local contract="$1" dir name names="" failed=0
  [ -d "$contract/contexts" ] || return 0
  for dir in "$contract"/contexts/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if [ -f "$dir/PRD.md" ] && [ -f "$dir/PROGRESS.md" ]; then
      if [[ "$name" =~ $name_re ]]; then names="${names}${name}"$'\n'
      else echo "FAIL: context $name is not a lowercase kebab-case name" >&2; failed=1; fi
    elif [ -f "$dir/PRD.md" ] || [ -f "$dir/PROGRESS.md" ]; then
      echo "FAIL: context $name lacks PRD.md or PROGRESS.md" >&2; failed=1
    fi
  done
  printf '%s' "$names" | LC_ALL=C sort
  [ "$failed" -eq 0 ]
}

# Context names from the first column of the index's `## Contexts` table.
index_names() {
  awk '
    /^#+ / { in_section = ($0 ~ /^#+ Contexts[[:space:]]*$/); next }
    !in_section || !/^\|/ { next }
    /^\|[-: |]+\|$/ { next }
    {
      n = split($0, cells, "|"); cell = cells[2]; gsub(/^[ \t]+|[ \t]+$/, "", cell)
      if (cell ~ /^`[^`]+`$/) { gsub(/`/, "", cell); print cell }
    }
  ' "$1/PRD.md" | LC_ALL=C sort -u
}

has_heading() { grep -Eq "^#+ $2[[:space:]]*$" "$1"; }

# The first backticked token of each bullet in the named section.
section_tokens() {
  awk -v heading="$2" '
    /^#+ / { in_section = ($0 ~ ("^#+ " heading "[[:space:]]*$")); next }
    in_section && /^[ \t]*[-*] / { if (match($0, /`[^`]+`/)) print substr($0, RSTART + 1, RLENGTH - 2) }
  ' "$1"
}

cmd_list() {
  [ "$#" -eq 1 ] || usage
  require_contract "$1"
  contexts_of "$1"
}

cmd_gate() {
  [ "$#" -eq 1 ] || usage
  local contract="$1" failed=0 names="" name dep prd
  require_contract "$contract"
  [ -f "$contract/PRD.md" ] && [ -f "$contract/PROGRESS.md" ] || { echo "FAIL: contract lacks PRD.md or PROGRESS.md: $contract" >&2; failed=1; }
  names="$(contexts_of "$contract")" || failed=1

  [ ! -f "$contract/PRD.md" ] || bash "$here/prd-size-gate.sh" "$contract/PRD.md" || failed=1
  [ ! -f "$contract/PROGRESS.md" ] || bash "$here/tracker-gate.sh" "$contract/PROGRESS.md" || failed=1
  [ ! -f "$contract/PRD.md" ] || [ ! -f "$contract/PROGRESS.md" ] || bash "$here/prd-fold-gate.sh" "$contract/PRD.md" "$contract/PROGRESS.md" || failed=1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    bash "$here/prd-size-gate.sh" "$contract/contexts/$name/PRD.md" || failed=1
    bash "$here/tracker-gate.sh" "$contract/contexts/$name/PROGRESS.md" || failed=1
    bash "$here/prd-fold-gate.sh" "$contract/contexts/$name/PRD.md" "$contract/contexts/$name/PROGRESS.md" || failed=1
  done <<<"$names"

  if [ -d "$contract/contexts" ] && [ -f "$contract/PRD.md" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      printf '%s\n' "$names" | grep -qxF -- "$name" || { echo "FAIL: index lists context $name without a directory" >&2; failed=1; }
    done <<<"$(index_names "$contract")"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      index_names "$contract" | grep -qxF -- "$name" || { echo "FAIL: context $name has no row in the index Contexts table" >&2; failed=1; }
      prd="$contract/contexts/$name/PRD.md"
      [ -n "$(section_tokens "$prd" Scope)" ] || { echo "FAIL: context $name declares no scope" >&2; failed=1; }
      if has_heading "$prd" 'Depends on'; then
        while IFS= read -r dep; do
          [ -n "$dep" ] || continue
          if [ "$dep" = "$name" ]; then echo "FAIL: context $name depends on itself" >&2; failed=1
          elif ! printf '%s\n' "$names" | grep -qxF -- "$dep"; then echo "FAIL: context $name depends on unknown context $dep" >&2; failed=1; fi
        done <<<"$(section_tokens "$prd" 'Depends on')"
      else
        echo "FAIL: context $name declares no dependencies section" >&2; failed=1
      fi
    done <<<"$names"
  fi

  [ "$failed" -eq 0 ] || { echo "FAIL: contract gate ($contract)" >&2; exit 1; }
  printf 'PASS: contract gate (%s)\n' "$contract"
}

cmd_owner() {
  [ "$#" -ge 2 ] || usage
  local contract="$1" names name glob scopes="" path matches; shift
  require_contract "$contract"
  names="$(contexts_of "$contract")" || exit 1
  if [ -z "$names" ]; then
    for path in "$@"; do printf '%s\troot\n' "$path"; done
    return 0
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    while IFS= read -r glob; do
      [ -n "$glob" ] || continue
      scopes="${scopes}${name}"$'\t'"${glob}"$'\n'
    done <<<"$(section_tokens "$contract/contexts/$name/PRD.md" Scope)"
  done <<<"$names"
  for path in "$@"; do
    matches=""
    while IFS=$'\t' read -r name glob; do
      [ -n "$name" ] || continue
      # shellcheck disable=SC2053
      if [[ "$path" == $glob ]]; then matches="${matches}${name}"$'\n'; fi
    done <<<"$scopes"
    matches="$(printf '%s' "$matches" | LC_ALL=C sort -u | paste -sd, -)"
    case "$matches" in
      "") printf '%s\tnone\n' "$path" ;;
      *,*) printf '%s\tambiguous:%s\n' "$path" "$matches" ;;
      *) printf '%s\t%s\n' "$path" "$matches" ;;
    esac
  done
}

[ "$#" -ge 1 ] || usage
command="$1"; shift
case "$command" in
  list) cmd_list "$@" ;;
  gate) cmd_gate "$@" ;;
  owner) cmd_owner "$@" ;;
  *) usage ;;
esac
