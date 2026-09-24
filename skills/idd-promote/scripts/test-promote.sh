#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="${PROMOTE_SCRIPT:-$root/skills/idd-promote/scripts/promote.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export PROMOTE_TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# A fake gh over state files: the repository integrates on dev with main as its
# private release branch, so protect-main.sh verifies the merge settings alone.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${PROMOTE_TEST_ROOT:?}"
key="${*: -1}"
case "$1 $2" in
  "repo view") echo example/app;;
  "pr list") cat "$root/open-pr" 2>/dev/null || true;;
  "pr create")
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --title) echo "$2" > "$root/title";;
        --body) printf '%s' "$2" > "$root/body";;
      esac
      shift
    done
    echo 9 > "$root/open-pr"; echo OPEN > "$root/state"
    echo https://github.com/example/app/pull/9;;
  "pr view")
    case "$key" in
      .state) cat "$root/state";;
      .isDraft) echo false;;
      .title) cat "$root/title";;
      .reviewDecision) cat "$root/review" 2>/dev/null || echo APPROVED;;
      .mergeStateStatus) cat "$root/merge-state";;
      .headRefOid) echo headsha;;
      '.body // ""') cat "$root/body";;
      '.mergeCommit.oid // ""') echo mergesha;;
      *) echo "unexpected pr view: $*" >&2; exit 2;;
    esac;;
  "pr merge")
    for arg in "$@"; do [ "$arg" != --merge ] || touch "$root/merge-method"; done
    while [ "$#" -gt 0 ]; do [ "$1" = --subject ] && echo "$2" > "$root/subject"; shift; done
    echo MERGED > "$root/state";;
  "api repos/example/app")
    case "$key" in
      .default_branch) cat "$root/default";;
      .visibility) echo private;;
      *) echo "true true false true PR_TITLE PR_BODY";;
    esac;;
  "api repos/example/app/branches/main") echo main;;
  "api repos/example/app/compare/main...dev")
    case "$key" in
      .ahead_by) cat "$root/ahead";;
      *) printf -- '- feat: add the widget (#4)\n- fix: keep the widget steady (#5)\n';;
    esac;;
  "api repos/example/app/commits/mergesha") cat "$root/parents";;
  *) echo "unexpected gh: $*" >&2; exit 2;;
esac
FAKE
chmod +x "$tmp/bin/gh"

fresh() {
  rm -f "$tmp"/{open-pr,state,title,body,review,subject,merge-method}
  echo dev > "$tmp/default"; echo 2 > "$tmp/ahead"; echo CLEAN > "$tmp/merge-state"
  echo "mainsha headsha" > "$tmp/parents"
}
fail() { echo "$*" >&2; exit 1; }
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "promote accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) fail "promote rejected $desc for the wrong reason: $err";; esac
}

# --- open and merge in one run, with a merge commit and an N-4 subject ----------
fresh
out="$(bash "$script" example/app)"
case "$out" in "integration=dev release=main"*) ;; *) fail "state the branches first: $out";; esac
[ "$(cat "$tmp/title")" = "chore(release): promote dev to main" ] || fail "wrong title"
grep -q '^- fix: keep the widget steady (#5)$' "$tmp/body" || fail "body must list the commits"
[ -f "$tmp/merge-method" ] || { echo "promotion must use a merge commit" >&2; exit 1; }
[ "$(cat "$tmp/subject")" = "chore(release): promote dev to main (#9)" ] || fail "wrong subject"
case "$out" in *"PROMOTED pr=9 merge=mergesha"*) ;; *) fail "missing PROMOTED line: $out";; esac

# --- --open-only stops for review; a rerun reuses the open PR --------------------
fresh
out="$(bash "$script" --open-only example/app)"
case "$out" in *"OPENED pr=9"*"awaits review"*) ;; *) echo "--open-only: $out" >&2; exit 1;; esac
[ ! -f "$tmp/merge-method" ] || { echo "--open-only must not merge" >&2; exit 1; }
out="$(bash "$script" example/app)"
case "$out" in
  *OPENED*) fail "a rerun must reuse the open PR";;
  *PROMOTED*) ;;
  *) fail "rerun: $out";;
esac

# --- nothing ahead, no release branch, or a blocked PR stop without merging -------
fresh; echo 0 > "$tmp/ahead"
out="$(bash "$script" example/app)"
case "$out" in *"NOTHING to promote"*) ;; *) echo "nothing ahead: $out" >&2; exit 1;; esac
fresh; echo main > "$tmp/default"
refuses "a single-branch repository" "nothing to promote" bash "$script" example/app
fresh; echo BLOCKED > "$tmp/merge-state"
refuses "a blocked PR" "BLOCKED by a repository rule" bash "$script" example/app
[ ! -f "$tmp/merge-method" ] || { echo "a blocked PR must not merge" >&2; exit 1; }
fresh; echo CHANGES_REQUESTED > "$tmp/review"
refuses "requested changes" "requested changes" bash "$script" example/app
fresh; echo "headsha" > "$tmp/parents"
refuses "a non-merge promotion commit" "is not a merge of dev" bash "$script" example/app
refuses "extra arguments" "usage:" bash "$script" example/app extra

echo "promote tests passed"
