#!/usr/bin/env bash
# Deterministic publication-exposure scan for one implementation repository.
#
#   scan-exposure.sh REPO_DIR [TERM ...]
#
# Scans every commit message and every unique blob reachable from every local ref,
# remote ref, and retained refs/pull/*/head against the mandatory denylist plus any
# caller-supplied terms. Prints one TSV line per hit and exits 1 when anything matches.
#
# A commit-message hit is reported UNPURGEABLE: the provider retains pull-request refs
# permanently, so no history rewrite reaches it.
set -uo pipefail

repo="${1:?usage: scan-exposure.sh REPO_DIR [TERM ...]}"; shift
cd "$repo" || exit 2
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository: $repo" >&2; exit 2; }

# Mandatory minimums. Callers add the companion PRD owner/name/URL/local path, every
# private companion repository and document, and any real organization, product, or alias.
TERMS=("[removed]" "[removed]" "[removed]" "[removed]" "[removed]" "[removed]" "$@")

SECRETS=(
  'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
  'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}'
  '-----BEGIN[[:space:]]+[A-Z]*[[:space:]]*PRIVATE[[:space:]]+KEY'
  'xox[baprs]-[A-Za-z0-9-]{10,}|sk_live_[A-Za-z0-9]{16,}|AIza[0-9A-Za-z_-]{30,}'
)

# A term matches by its bare stem: a trailing file extension is stripped so a term written
# as a filename still matches the same name used without one, and runs of punctuation or
# space are interchangeable. Short all-alphanumeric stems get word boundaries so an
# abbreviation does not match inside an unrelated word.
to_regex() {
  local t="$1" out="" run="" i c
  t="${t%.[A-Za-z0-9][A-Za-z0-9]}"
  t="${t%.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]}"
  t="${t%.[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]}"
  for ((i = 0; i < ${#t}; i++)); do
    c="${t:i:1}"
    if [[ "$c" == [A-Za-z0-9] ]]; then out+="$c"; run+="$c"; else out+='[^[:alnum:]]*'; fi
  done
  [ -n "$out" ] || return 1
  if [ "$out" = "$run" ] && [ "${#run}" -le 5 ]; then
    printf '(^|[^[:alnum:]])%s([^[:alnum:]]|$)' "$out"
  else
    printf '%s' "$out"
  fi
}

PATTERNS=()
for t in "${TERMS[@]}"; do
  [ -n "$t" ] || continue
  rx="$(to_regex "$t")" && PATTERNS+=("term|$t|$rx")
done
for rx in "${SECRETS[@]}"; do PATTERNS+=("secret|credential|$rx"); done

# Retained pull-request refs are part of the public surface; fetch them best-effort.
if git remote get-url origin >/dev/null 2>&1; then
  GIT_TERMINAL_PROMPT=0 git fetch -q origin '+refs/pull/*/head:refs/remotes/origin/pr/*' 2>/dev/null \
    || echo "warning: could not fetch refs/pull/*/head — retained PR refs unscanned" >&2
fi

out="$(mktemp)"; trap 'rm -f "$out"' EXIT

scan() { # $1=kind $2=source ; stdin=content ; prints hits only
  local kind="$1" src="$2" content entry label term rx found
  content="$(cat)"
  for entry in "${PATTERNS[@]}"; do
    label="${entry%%|*}"; term="${entry#*|}"; rx="${term#*|}"; term="${term%%|*}"
    # -e is required: a pattern may legitimately start with "-" (private-key headers).
    found="$(printf '%s' "$content" | grep -o -i -E -e "$rx" 2>/dev/null | sort -u | tr '\n' ' ')"
    [ -n "$found" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$kind" "$src" "$label" "$term" "${found:0:100}"
  done
}

while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  git log -1 --format='%s%n%b' "$sha" | scan commit "${sha:0:9}" >>"$out"
done < <(git rev-list --all 2>/dev/null)

while IFS= read -r line; do
  [ -n "$line" ] || continue
  git cat-file blob "${line%%	*}" 2>/dev/null | scan blob "${line#*	}" >>"$out"
done < <(
  for ref in $(git for-each-ref --format='%(refname)'); do
    git ls-tree -r "$ref" 2>/dev/null | awk '$2 == "blob" { print $3 "\t" substr($0, index($0, "\t") + 1) }'
  done | sort -u
)

git for-each-ref --format='%(refname)' | scan refname refs >>"$out"

sort -u "$out"
hits="$(sort -u "$out" | grep -c . || true)"
commit_hits="$(sort -u "$out" | grep -c '^commit	' || true)"

if [ "$commit_hits" -gt 0 ]; then
  echo "UNPURGEABLE: $commit_hits commit-message match(es). No history rewrite reaches the provider's retained pull-request refs — decide before changing visibility." >&2
fi
[ "$hits" -eq 0 ] || { echo "BLOCKED: $hits exposure match(es)." >&2; exit 1; }
echo "exposure scan clean"
