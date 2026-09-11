#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${PROGRESS_PR_SCRIPT:-$root/scripts/progress-pr.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$tmp/bin"
export PROGRESS_TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# The fake gh keeps one PR in state files: open-pr holds "<number> <branch>" while
# it is open, and a merge performs a real squash of the head onto origin/main.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${PROGRESS_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then
  [[ "$*" == *nameWithOwner* ]] && echo example/demo-prd || echo main
elif [ "$1 $2" = "pr list" ]; then
  cat "$root/open-pr"
elif [ "$1 $2" = "pr create" ]; then
  while [ "$#" -gt 0 ]; do case "$1" in --head) head="$2"; shift;; esac; shift; done
  echo "7 $head" > "$root/open-pr"; echo "$head" > "$root/pr-head"; echo OPEN > "$root/pr-state"
  printf 'x' >> "$root/create-count"; echo "https://github.com/example/demo-prd/pull/7"
elif [ "$1 $2" = "pr view" ]; then
  case "${*: -1}" in
    .isDraft) echo false;;
    .reviewDecision) cat "$root/review";;
    .mergeStateStatus) cat "$root/merge-state";;
    .headRefOid) git fetch -q origin; git rev-parse "origin/$(cat "$root/pr-head")";;
    .state) cat "$root/pr-state";;
    '.mergeCommit.oid // ""') cat "$root/merge-oid";;
    *) echo "unexpected pr view key: ${*: -1}" >&2; exit 2;;
  esac
elif [ "$1 $2" = "pr merge" ]; then
  while [ "$#" -gt 0 ]; do
    case "$1" in --subject) subject="$2"; shift;; --body) body="$2"; shift;; --match-head-commit) match="$2"; shift;; esac
    shift
  done
  head="$(cat "$root/pr-head")"; git fetch -q origin
  [ "$match" = "$(git rev-parse "origin/$head")" ] || { echo "Head branch was modified" >&2; exit 1; }
  oid="$(git commit-tree "$(git rev-parse "origin/$head^{tree}")" -p "$(git rev-parse origin/main)" -m "$subject" -m "$body")"
  git push -q --no-verify origin "$oid:main"
  echo "$oid" > "$root/merge-oid"; echo MERGED > "$root/pr-state"; : > "$root/open-pr"; printf 'x' >> "$root/merge-count"
elif [ "$1 $2" = "api graphql" ]; then
  cat "$root/unresolved"
elif [ "$1" = api ]; then
  oid="${2##*/}"; git fetch -q origin
  case "${*: -1}" in
    '.parents | length') git rev-list --parents -n1 "$oid" | wc -w | awk '{print $1-1}';;
    .commit.message) git log -1 --format=%B "$oid";;
  esac
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"

fresh() {
  rm -rf "$tmp/origin.git" "$tmp/demo-prd" "$tmp"/open-pr "$tmp"/pr-* "$tmp"/merge-* "$tmp"/create-count
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/demo-prd" 2>/dev/null
  ( cd "$tmp/demo-prd"; git switch -q -c main 2>/dev/null || true
    printf 'prd\n' > PRD.md; printf 'progress\n' > PROGRESS.md; git add .; git commit -qm "docs: init"
    git push -q -u origin main )
  : > "$tmp/open-pr"; echo "" > "$tmp/review"; echo CLEAN > "$tmp/merge-state"; echo 0 > "$tmp/unresolved"
}
run() { bash "$script" "$@"; }
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "progress-pr accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "progress-pr rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
  [ ! -f "$tmp/merge-count" ] || { echo "a refusal must not merge ($desc)" >&2; exit 1; }
}
prd="$tmp/demo-prd"
on() { git -C "$prd" symbolic-ref --short HEAD; }

# --- sync with no batch stays on main and guards it ------------------------------
fresh
out="$(run sync "$prd")"
[ "$out" = "$(printf 'branch=main\npr=')" ] || { echo "unexpected sync output: $out" >&2; exit 1; }
printf 'direct\n' >> "$prd/PROGRESS.md"; git -C "$prd" commit -qam "progress: direct"
if err="$(git -C "$prd" push -q origin main 2>&1)"; then echo "the guard must refuse a direct push to main" >&2; exit 1; fi
case "$err" in *"changes only through a pull request"*) ;; *) echo "wrong guard refusal: $err" >&2; exit 1;; esac
git -C "$prd" reset -q --hard origin/main

# --- the first push opens the batch; main is untouched ---------------------------
printf 'row 1\n' >> "$prd/PROGRESS.md"
out="$(run push "$prd" "progress: reconcile example/demo#1" PROGRESS.md)"
branch="$(sed -n 's/^branch=//p' <<<"$out")"
[[ "$branch" =~ ^progress/[0-9]{8}-[0-9]{6}$ ]] || { echo "unexpected batch branch: $branch" >&2; exit 1; }
grep -qx 'pr=7' <<<"$out" || { echo "push must report the opened batch: $out" >&2; exit 1; }
[ "$(on)" = "$branch" ] || { echo "push must leave the checkout on the batch" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 1 ] || { echo "push must not change main" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = "$(git -C "$prd" rev-parse HEAD)" ] || { echo "the batch must be pushed" >&2; exit 1; }

# --- refusals before any commit ----------------------------------------------------
printf 'stray\n' >> "$prd/PRD.md"; printf 'row x\n' >> "$prd/PROGRESS.md"
refuses "a change outside the named paths" "outside the named paths" run push "$prd" "progress: reconcile example/demo#2" PROGRESS.md
git -C "$prd" checkout -q -- .
printf 'row x\n' >> "$prd/PROGRESS.md"
refuses "an untyped subject" "progress: <lowercase summary>" run push "$prd" "reconcile example/demo#2" PROGRESS.md
refuses "a sync over a dirty tree" "dirty PRD tree" run sync "$prd"
git -C "$prd" checkout -q -- .

# --- a second push joins the same batch, even after a sync from main ---------------
git -C "$prd" switch -q main
out="$(run sync "$prd")"
[ "$out" = "$(printf 'branch=%s\npr=7' "$branch")" ] || { echo "sync must check out the open batch: $out" >&2; exit 1; }
printf 'row 2\n' >> "$prd/PROGRESS.md"
run push "$prd" "progress: reconcile example/demo#2" PROGRESS.md >/dev/null
[ "$(cat "$tmp/create-count")" = x ] || { echo "a second push must not open a second batch" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count "$branch")" = 3 ] || { echo "the batch must carry both reconciles" >&2; exit 1; }

# --- merge refuses review state it must not bypass ---------------------------------
echo 1 > "$tmp/unresolved"
refuses "an unresolved review thread" "unresolved review thread" run merge "$prd" "progress: validate slice one"
echo 0 > "$tmp/unresolved"; echo CHANGES_REQUESTED > "$tmp/review"
refuses "requested changes" "requested changes" run merge "$prd" "progress: validate slice one"
echo "" > "$tmp/review"; echo DIRTY > "$tmp/merge-state"
refuses "a conflicting batch" "not CLEAN" run merge "$prd" "progress: validate slice one"
echo CLEAN > "$tmp/merge-state"
refuses "an untyped merge subject" "progress: <lowercase summary>" run merge "$prd" "Validate slice one"
echo "8 progress/other" >> "$tmp/open-pr"
refuses "two open batches" "More than one open progress batch" run merge "$prd" "progress: validate slice one"
echo "7 $branch" > "$tmp/open-pr"

# --- the milestone merge lands one squash commit and removes the batch -------------
out="$(run merge "$prd" "progress: validate slice one")"
grep -qx 'subject=progress: validate slice one (#7)' <<<"$out" || { echo "unexpected merge output: $out" >&2; exit 1; }
[ "$(on)" = main ] || { echo "merge must return to main" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 2 ] || { echo "the batch must land as exactly one commit" >&2; exit 1; }
[ "$(git -C "$prd" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "local main must equal origin" >&2; exit 1; }
want="$(printf 'progress: validate slice one (#7)\n\n- progress: reconcile example/demo#1\n- progress: reconcile example/demo#2')"
[ "$(git -C "$prd" log -1 --format=%B)" = "$want" ] || { echo "the landed body must list the batched reconciles" >&2; exit 1; }
[ "$(tail -2 "$prd/PROGRESS.md" | tr '\n' ' ')" = "row 1 row 2 " ] || { echo "merged tracker content must be checked out" >&2; exit 1; }
! git -C "$prd" show-ref --verify --quiet "refs/heads/$branch" || { echo "the local batch must be deleted" >&2; exit 1; }
! git -C "$tmp/origin.git" show-ref --verify --quiet "refs/heads/$branch" || { echo "the remote batch must be deleted" >&2; exit 1; }
out="$(run merge "$prd" "progress: validate slice one")"
[ "$out" = "no open progress batch; main at $(git -C "$prd" rev-parse --short HEAD)" ] || { echo "a merge with no batch must be a no-op: $out" >&2; exit 1; }

# --- someone else's pre-push hook is never overwritten -----------------------------
fresh
printf '#!/bin/sh\nexit 0\n' > "$prd/.git/hooks/pre-push"
err="$(run sync "$prd" 2>&1 >/dev/null)"
case "$err" in *"existing pre-push hook was left in place"*) ;; *) echo "a foreign hook must be reported: $err" >&2; exit 1;; esac
[ "$(cat "$prd/.git/hooks/pre-push")" = "$(printf '#!/bin/sh\nexit 0')" ] || { echo "a foreign hook must be left unchanged" >&2; exit 1; }

echo "IDD progress batch valid"
