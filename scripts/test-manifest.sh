#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${MANIFEST_SCRIPT:-$root/scripts/manifest.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

mk_repo() { mkdir -p "$1"; git -C "$1" init -q -b main; git -C "$1" remote add origin "https://github.com/$2.git"; }
commit_all() { git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
manifest_prd() { # $1 = contract path, remaining args = manifest rows (or "None declared.")
  local contract="$1"; shift
  { printf '# demo product requirements\n\n## Gold standard\n\n### Preserved artifacts\n\n'
    if [ "$1" = "None declared." ]; then printf 'None declared.\n'
    else printf '| Artifact | Repository | Path | Why not regenerable | Verified by |\n|---|---|---|---|---|\n'; printf '%s\n' "$@"; fi
    printf '\n## Requirements\n'; } > "$contract/PRD.md"
}
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "manifest accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "manifest rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
}

# --- reconstruct candidates: only classes with observed evidence -------------
mk_repo "$tmp/demo" example/demo
mkdir -p "$tmp/demo/schemas" "$tmp/demo/golden/cases" "$tmp/demo/docs" "$tmp/demo/src"
touch "$tmp/demo/CONSTITUTION.md" "$tmp/demo/schemas/v1.json" "$tmp/demo/golden/cases/a.txt" \
  "$tmp/demo/package-lock.json" "$tmp/demo/docs/ADR-001-storage.md" "$tmp/demo/src/main.sh" "$tmp/demo/README.md"
commit_all "$tmp/demo" init
candidates="$(bash "$script" candidates "$tmp/demo")"
expected="$(printf 'constitution\tCONSTITUTION.md\ndecision-log\tdocs/ADR-001-storage.md\ngolden-or-fixture\tgolden/\nlockfile\tpackage-lock.json\nschema\tschemas/')"
[ "$candidates" = "$expected" ] || { printf 'unexpected candidate list:\n%s\n' "$candidates" >&2; exit 1; }

# --- an explicit empty manifest ----------------------------------------------
mk_repo "$tmp/demo-prd" example/demo-prd
manifest_prd "$tmp/demo-prd" "None declared."
printf '# progress\n' > "$tmp/demo-prd/PROGRESS.md"; printf '# conventions\n' > "$tmp/demo-prd/CLAUDE.md"
commit_all "$tmp/demo-prd" init
bash "$script" drift "$tmp/demo-prd" | grep -q '^PASS: manifest drift' || { echo "drift rejected a clean contract" >&2; exit 1; }
bash "$script" verify "$tmp/demo-prd" "$tmp/demo" | grep -q '^PASS: manifest verify (None declared)' || { echo "verify rejected an explicit empty manifest" >&2; exit 1; }

# --- a contract tracking a file its manifest does not name -------------------
printf 'stray\n' > "$tmp/demo-prd/notes.md"; commit_all "$tmp/demo-prd" stray
before="$(git -C "$tmp/demo-prd" rev-parse HEAD)$(git -C "$tmp/demo-prd" status --porcelain)"
refuses "an unlisted tracked file" "DRIFT: tracked but not named by the manifest: notes.md" bash "$script" drift "$tmp/demo-prd"
[ "$before" = "$(git -C "$tmp/demo-prd" rev-parse HEAD)$(git -C "$tmp/demo-prd" status --porcelain)" ] || { echo "drift changed the contract" >&2; exit 1; }
git -C "$tmp/demo-prd" rm -q notes.md; commit_all "$tmp/demo-prd" "drop stray"

# --- rows bound to either repository -----------------------------------------
printf 'charter\n' > "$tmp/demo-prd/PROBLEM.md"
manifest_prd "$tmp/demo-prd" \
  '| Constitution | `example/demo` | `CONSTITUTION.md` | Evolution law | Read against its articles |' \
  '| Problem charter | `example/demo-prd` | `PROBLEM.md` | Original framing | Existence |'
commit_all "$tmp/demo-prd" manifest
bash "$script" drift "$tmp/demo-prd" | grep -q '^PASS' || { echo "drift rejected a manifest-named contract file" >&2; exit 1; }
out="$(bash "$script" verify "$tmp/demo-prd" "$tmp/demo")"
grep -q 'present: Constitution at example/demo:CONSTITUTION.md' <<<"$out" || { echo "verify did not bind the implementation row: $out" >&2; exit 1; }
grep -q 'present: Problem charter at example/demo-prd:PROBLEM.md' <<<"$out" || { echo "verify did not bind the contract row: $out" >&2; exit 1; }

# --- a row whose path is absent ----------------------------------------------
manifest_prd "$tmp/demo-prd" \
  '| Constitution | `example/demo` | `CONSTITUTION.md` | Evolution law | Read against its articles |' \
  '| Golden index | `example/demo` | `golden/INDEX.md` | Frozen case list | Existence |'
commit_all "$tmp/demo-prd" absent
refuses "a manifest row whose path is absent" "FAIL: missing artifact: Golden index expected at example/demo:golden/INDEX.md" bash "$script" verify "$tmp/demo-prd" "$tmp/demo"

# --- a contract with no manifest section at all ------------------------------
printf '# demo product requirements\n\n## Requirements\n' > "$tmp/demo-prd/PRD.md"; commit_all "$tmp/demo-prd" silent
refuses "a PRD without a manifest section" "no Preserved artifacts section" bash "$script" verify "$tmp/demo-prd" "$tmp/demo"
out="$(bash "$script" drift "$tmp/demo-prd" 2>&1 || true)"
grep -q 'treating the manifest as empty' <<<"$out" || { echo "drift did not note the missing section: $out" >&2; exit 1; }

echo "manifest tooling valid"
