#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: manifest.sh candidates IMPLEMENTATION_PATH
       manifest.sh drift CONTRACT_PATH
       manifest.sh verify CONTRACT_PATH IMPLEMENTATION_PATH
USAGE
  exit 64
}

# Harness instruction files a contract repository may track besides PRD.md,
# PROGRESS.md, and the artifacts its manifest names.
harness_files='CLAUDE.md AGENTS.md GEMINI.md .cursorrules .github/copilot-instructions.md'

normalize_github_remote() {
  local url="$1"
  url="${url%.git}"
  case "$url" in
    https://github.com/*) printf '%s\n' "${url#https://github.com/}" ;;
    http://github.com/*) printf '%s\n' "${url#http://github.com/}" ;;
    git@github.com:*) printf '%s\n' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s\n' "${url#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
}

repo_of() { # prints owner/name for a checkout, or nothing when it has no GitHub origin
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 0
  normalize_github_remote "$url" || true
}

require_repo() {
  git -C "$1" rev-parse --show-toplevel >/dev/null 2>&1 || { echo "Not a git repository: $1" >&2; exit 1; }
  (cd "$1" && git rev-parse --show-toplevel)
}

# Emits one line per manifest row: repository<TAB>path<TAB>artifact. Prints the
# single word NONE for an explicit empty manifest, and nothing at all when
# PRD.md has no Preserved artifacts section.
manifest_rows() {
  awk '
    /^#+ / { in_section = ($0 ~ /^#+ Preserved artifacts[[:space:]]*$/); next }
    !in_section { next }
    /None declared/ { print "NONE"; next }
    /^\|/ {
      if ($0 ~ /^\|[-: |]+\|$/) next
      n = split($0, cells, "|")
      for (i = 1; i <= n; i++) { gsub(/^[ \t`]+|[ \t`]+$/, "", cells[i]) }
      if (cells[2] == "Artifact") next
      if (cells[3] == "" || cells[4] == "") next
      printf "%s\t%s\t%s\n", cells[3], cells[4], cells[2]
    }
  ' "$1/PRD.md"
}

has_section() { grep -Eq '^#+ Preserved artifacts[[:space:]]*$' "$1/PRD.md"; }

cmd_candidates() {
  [ "$#" -eq 1 ] || usage
  local impl; impl="$(require_repo "$1")"
  git -C "$impl" ls-files | awk '
    function emit(class, path,   key) { key = class "\t" path; if (!(key in seen)) { seen[key] = 1; print key } }
    {
      path = $0; n = split(path, parts, "/"); lbase = tolower(parts[n]); lower = tolower(path)
      if (lbase == "constitution.md") emit("constitution", path)
      else if (lbase ~ /^(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|cargo\.lock|poetry\.lock|uv\.lock|gemfile\.lock|go\.sum|composer\.lock|pipfile\.lock|flake\.lock)$/) emit("lockfile", path)
      else if (lbase ~ /\.schema\.[a-z]+$/) emit("schema", path)
      else if (lbase == "decisions.md" || lbase ~ /^adr-[0-9]+.*\.md$/) emit("decision-log", path)
      else if (lbase ~ /protocol/ && lbase ~ /\.md$/) emit("protocol", path)
      else if (lower ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ && lower ~ /accept|cohort|record/) emit("dated-record", path)
      dir = ""
      for (i = 1; i < n; i++) {
        dir = dir parts[i] "/"; lp = tolower(parts[i])
        if (lp ~ /^(schema|schemas|rules|rulepack|rulepacks)$/) { emit("schema", dir); break }
        if (lp ~ /^(golden|goldens|fixture|fixtures|snapshots|__snapshots__)$/) { emit("golden-or-fixture", dir); break }
        if (lp ~ /^(adr|adrs|decisions)$/) { emit("decision-log", dir); break }
      }
    }
  ' | LC_ALL=C sort
}

cmd_drift() {
  [ "$#" -eq 1 ] || usage
  local contract contract_repo rows allowed tracked drift=0
  contract="$(require_repo "$1")"
  [ -f "$contract/PRD.md" ] && [ -f "$contract/PROGRESS.md" ] || { echo "Contract must contain PRD.md and PROGRESS.md: $contract" >&2; exit 1; }
  contract_repo="$(repo_of "$contract")"
  has_section "$contract" || echo "note: PRD.md has no Preserved artifacts section; treating the manifest as empty" >&2
  rows="$(manifest_rows "$contract" | grep -v '^NONE$' || true)"
  # A row is allowed here when it names this contract repository, or any
  # repository when the contract has no resolvable GitHub origin.
  allowed="$(printf '%s\n' "$rows" | awk -F'\t' -v repo="$contract_repo" 'NF >= 2 && (repo == "" || $1 == repo) { print $2 }')"
  tracked="$(git -C "$contract" ls-files)"
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case " $harness_files " in *" $file "*) continue;; esac
    [ "$file" = PRD.md ] || [ "$file" = PROGRESS.md ] && continue
    printf '%s\n' "$allowed" | grep -qxF -- "$file" && continue
    echo "DRIFT: tracked but not named by the manifest: $file" >&2
    drift=1
  done <<<"$tracked"
  [ "$drift" -eq 0 ] || exit 1
  printf 'PASS: manifest drift (%s)\n' "$contract"
}

cmd_verify() {
  [ "$#" -eq 2 ] || usage
  local contract impl contract_repo impl_repo rows failed=0 repo path artifact base
  contract="$(require_repo "$1")"; impl="$(require_repo "$2")"
  [ -f "$contract/PRD.md" ] || { echo "Contract must contain PRD.md: $contract" >&2; exit 1; }
  contract_repo="$(repo_of "$contract")"; impl_repo="$(repo_of "$impl")"
  [ -n "$contract_repo" ] && [ -n "$impl_repo" ] || { echo "Both checkouts need a GitHub origin to bind manifest rows" >&2; exit 1; }
  has_section "$contract" || { echo "FAIL: PRD.md has no Preserved artifacts section; the contract is silent about what a regeneration must carry" >&2; exit 1; }
  rows="$(manifest_rows "$contract")"
  if [ "$rows" = NONE ]; then printf 'PASS: manifest verify (None declared)\n'; return 0; fi
  [ -n "$rows" ] || { echo "FAIL: Preserved artifacts section has neither rows nor an explicit 'None declared'" >&2; exit 1; }
  while IFS=$'\t' read -r repo path artifact; do
    [ -n "$repo" ] || continue
    if [ "$repo" = "$contract_repo" ]; then base="$contract"
    elif [ "$repo" = "$impl_repo" ]; then base="$impl"
    else echo "FAIL: $artifact names repository $repo, which is neither $contract_repo nor $impl_repo" >&2; failed=1; continue; fi
    if [ -e "$base/$path" ]; then printf 'present: %s at %s:%s\n' "$artifact" "$repo" "$path"
    else echo "FAIL: missing artifact: $artifact expected at $repo:$path" >&2; failed=1; fi
  done <<<"$rows"
  [ "$failed" -eq 0 ] || exit 1
  printf 'PASS: manifest verify (%s)\n' "$contract"
}

[ "$#" -ge 1 ] || usage
command="$1"; shift
case "$command" in
  candidates) cmd_candidates "$@" ;;
  drift) cmd_drift "$@" ;;
  verify) cmd_verify "$@" ;;
  *) usage ;;
esac
