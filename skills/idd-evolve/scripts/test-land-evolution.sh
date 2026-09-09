#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/skills/idd-evolve/scripts/land-evolution.sh"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$tmp/bin"
export LANDEV_TEST_ROOT="$tmp"
export PATH="$tmp/bin:$PATH"

# The fake gh answers PR fields from state files and performs a real squash on
# merge: one commit-tree of the head onto origin/main, pushed to main, and the
# head branch deleted unless LANDEV_TEST_KEEP_REMOTE simulates that setting off.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${LANDEV_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then
  [[ "$*" == *nameWithOwner* ]] && echo example/demo || echo main
elif [ "$1 $2" = "pr view" ]; then
  key="${*: -1}"
  case "$key" in
    .state) cat "$root/pr-state";;
    .baseRefName) cat "$root/pr-base";;
    .headRefName) cat "$root/pr-head";;
    .isDraft) cat "$root/pr-draft";;
    .isCrossRepository) echo false;;
    .title) cat "$root/pr-title";;
    .mergeStateStatus) cat "$root/pr-merge-state";;
    '.body // ""') cat "$root/pr-body";;
    .mergeCommit.oid) cat "$root/merge-oid";;
    *) echo "unexpected pr view key: $key" >&2; exit 2;;
  esac
elif [ "$1 $2" = "pr merge" ]; then
  subject=""; body=""
  while [ "$#" -gt 0 ]; do
    case "$1" in --subject) subject="$2"; shift;; --body) body="$2"; shift;; esac
    shift
  done
  [ -z "${LANDEV_TEST_WRONG_SUBJECT:-}" ] || subject="$LANDEV_TEST_WRONG_SUBJECT"
  head="$(cat "$root/pr-head")"
  git fetch -q origin
  tree="$(git rev-parse "origin/$head^{tree}")"
  oid="$(git commit-tree "$tree" -p "$(git rev-parse origin/main)" -m "$subject (#5)" -m "$body")"
  git push -q origin "$oid:main"
  [ -n "${LANDEV_TEST_KEEP_REMOTE:-}" ] || git push -q origin --delete "$head"
  echo "$oid" > "$root/merge-oid"; echo MERGED > "$root/pr-state"; printf 'x' >> "$root/merge-count"
elif [ "$1" = api ]; then
  oid="${2##*/}"; key="${*: -1}"
  case "$key" in
    '.parents | length') git fetch -q origin; git rev-list --parents -n1 "$oid" | wc -w | awk '{print $1-1}';;
    .commit.message) git fetch -q origin; git log -1 --format=%B "$oid";;
    *) echo "unexpected api key: $key" >&2; exit 2;;
  esac
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"

fresh() { # origin with main plus a one-commit evolve branch, a clone on main holding that branch too
  rm -rf "$tmp/origin.git" "$tmp/work" "$tmp"/pr-* "$tmp"/merge-*
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
  ( cd "$tmp/work"; git switch -q -c main 2>/dev/null || true
    printf 'a\n' > a.txt; git add a.txt; git commit -qm "chore: init"; git push -q -u origin main
    git switch -q -c evolve/reviewed; printf 'a2\n' > a.txt; printf 'z\n' > z.txt; git add a.txt z.txt
    git commit -qm "evolve: route kept evolutions through pull requests"; git push -q -u origin evolve/reviewed
    git switch -q main )
  echo OPEN > "$tmp/pr-state"; echo main > "$tmp/pr-base"; echo evolve/reviewed > "$tmp/pr-head"; echo false > "$tmp/pr-draft"
  printf 'evolve: route kept evolutions through pull requests' > "$tmp/pr-title"; echo CLEAN > "$tmp/pr-merge-state"
  printf 'Evidence: reviewed.\n\nKept: one branch.' > "$tmp/pr-body"
}
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "land-evolution accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "land-evolution rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
  [ ! -f "$tmp/merge-count" ] || { echo "a refused landing must not merge ($desc)" >&2; exit 1; }
}
run() { (cd "$tmp/work" && bash "$script" 5); }

# --- the happy path from main -----------------------------------------------------
fresh
out="$(run)"
case "$out" in "landed example/demo#5 as "*": evolve: route kept evolutions through pull requests (#5)") ;; *) echo "unexpected output: $out" >&2; exit 1;; esac
[ "$(git -C "$tmp/work" symbolic-ref --short HEAD)" = main ] || { echo "must end on main" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "local main must equal the landed origin main" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-list --count HEAD)" = 2 ] || { echo "the squash must add exactly one commit" >&2; exit 1; }
[ "$(git -C "$tmp/work" log -1 --format=%B)" = "$(printf 'evolve: route kept evolutions through pull requests (#5)\n\nEvidence: reviewed.\n\nKept: one branch.')" ] || { echo "landed message must be the PR title and body" >&2; exit 1; }
[ "$(cat "$tmp/work/z.txt")" = z ] || { echo "landed content must be checked out" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "local evolve branch must be deleted" >&2; exit 1; }
! git -C "$tmp/origin.git" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "origin evolve branch must be deleted" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/remotes/origin/evolve/reviewed || { echo "the stale remote-tracking ref must be pruned" >&2; exit 1; }

# --- from the evolve branch itself, and when the provider leaves the branch behind --
fresh; git -C "$tmp/work" switch -q evolve/reviewed
LANDEV_TEST_KEEP_REMOTE=1 run >/dev/null
[ "$(git -C "$tmp/work" symbolic-ref --short HEAD)" = main ] || { echo "must switch to main before deleting the branch" >&2; exit 1; }
! git -C "$tmp/origin.git" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the script must delete a remote branch the provider kept" >&2; exit 1; }

# --- refusals leave everything untouched --------------------------------------------
fresh; echo MERGED > "$tmp/pr-state"; refuses "an already merged PR" "is MERGED, not OPEN" run
fresh; echo develop > "$tmp/pr-base"; refuses "a PR onto another base" "targets develop, not main" run
fresh; echo issue/3-fix > "$tmp/pr-head"; refuses "a non-evolve head" "not an evolve/<slug> branch (N-3)" run
fresh; echo true > "$tmp/pr-draft"; refuses "a draft" "is a draft" run
fresh; printf 'Route kept evolutions through pull requests' > "$tmp/pr-title"; refuses "an untyped title" "must be an N-4 subject" run
fresh; printf 'evolve: %s' "$(printf 'x%.0s' $(seq 1 70))" > "$tmp/pr-title"; refuses "a long title" "exceeds 72" run
fresh; echo BLOCKED > "$tmp/pr-merge-state"; refuses "a blocked PR" "resolve every review thread" run
fresh; echo DIRTY > "$tmp/pr-merge-state"; refuses "a conflicting PR" "conflicts with main" run
fresh; echo UNKNOWN > "$tmp/pr-merge-state"; refuses "an uncomputed merge state" "not CLEAN" run
fresh; printf 'dirty\n' > "$tmp/work/a.txt"; refuses "a dirty working tree" "dirty working tree" run
refuses "a non-numeric PR" "usage:" bash -c "cd '$tmp/work' && bash '$script' abc"
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 1 ] || { echo "refusals must leave origin main alone" >&2; exit 1; }

# --- a landed subject that differs from the title is disclosed after the merge --------
fresh
if err="$(cd "$tmp/work" && LANDEV_TEST_WRONG_SUBJECT='wrong subject' bash "$script" 5 2>&1 >/dev/null)"; then echo "a wrong landed subject must fail" >&2; exit 1; fi
case "$err" in *"Landed subject is 'wrong subject (#5)'"*) ;; *) echo "wrong reason for a wrong landed subject: $err" >&2; exit 1;; esac

# --- running from a mutable source ---------------------------------------------
# The checkout may serve the installed skill, so the mid-sequence branch switch
# can rewrite this very script on disk; everything after it must already be parsed.
fresh; git -C "$tmp/work" switch -q evolve/reviewed
real_git="$(command -v git)"
cp "$script" "$tmp/copy.sh"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = switch ] && [ -n "\${REWRITE_TARGET:-}" ]; then yes 'exit 99' | head -4000 > "\$REWRITE_TARGET"; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
out="$(cd "$tmp/work" && REWRITE_TARGET="$tmp/copy.sh" bash "$tmp/copy.sh" 5 2>&1)" || { echo "the script failed once its own source was rewritten mid-run: $out" >&2; exit 1; }
case "$out" in "landed example/demo#5 as "*) ;; *) echo "a rewritten source did not report completion: $out" >&2; exit 1;; esac
rm -f "$tmp/bin/git"

echo "land-evolution tests passed"
