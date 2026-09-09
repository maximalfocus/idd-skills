#!/usr/bin/env bash
set -euo pipefail

# Land one reviewed evolution PR on the maintainer's explicit instruction:
# validate it, squash-merge with the N-4 title as subject and the PR body as
# body, confirm the landed commit, refresh the default branch in this checkout,
# and delete the evolve branch locally and on origin. Never merges anything the
# provider's rules still block, never force-pushes.
#
#   land-evolution.sh PR

# The whole sequence is one function so that bash parses it completely before
# executing anything: the mid-sequence branch switch may rewrite this very file
# when the checkout serves the installed skill, and a script read incrementally
# would then execute the rewritten tail.
land_evolution_main() {
usage() { echo "usage: land-evolution.sh PR" >&2; exit 64; }
[ "$#" -eq 1 ] && [[ "$1" =~ ^[0-9]+$ ]] || usage
pr="$1"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repository" >&2; exit 1; }
cd "$root"
[ -z "$(git status --porcelain)" ] || { echo "Refusing to land with a dirty working tree" >&2; exit 1; }
git remote get-url origin >/dev/null
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
default="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"

field() { gh pr view "$pr" --repo "$repo" --json "$1" --jq ".$1"; }
state="$(field state)"
[ "$state" = OPEN ] || { echo "PR #$pr is $state, not OPEN" >&2; exit 1; }
base="$(field baseRefName)"; head="$(field headRefName)"
[ "$base" = "$default" ] || { echo "PR #$pr targets $base, not $default" >&2; exit 1; }
[[ "$head" =~ ^evolve/[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "PR #$pr head is '$head', not an evolve/<slug> branch (N-3)" >&2; exit 1; }
[ "$(field isDraft)" = false ] || { echo "PR #$pr is a draft" >&2; exit 1; }
[ "$(field isCrossRepository)" = false ] || { echo "PR #$pr comes from a fork" >&2; exit 1; }
title="$(field title)"
types='feat|fix|docs|test|refactor|perf|chore|build|ci|evolve'
[[ "$title" =~ ^($types)(\([a-z0-9]+(-[a-z0-9]+)*\))?:\ [a-z] ]] || {
  echo "PR #$pr title must be an N-4 subject, since the squash merge takes it verbatim: $title" >&2; exit 1; }
[ "${#title}" -le 72 ] || { echo "PR #$pr title exceeds 72 characters (N-4): ${#title}" >&2; exit 1; }
merge_state="$(field mergeStateStatus)"
case "$merge_state" in
  CLEAN) ;;
  BLOCKED) echo "PR #$pr is BLOCKED by a repository rule: resolve every review thread and rerun" >&2; exit 1;;
  DIRTY) echo "PR #$pr conflicts with $default; rebase the evolve branch and rerun" >&2; exit 1;;
  *) echo "PR #$pr merge state is $merge_state, not CLEAN; rerun once GitHub reports it clean" >&2; exit 1;;
esac
body="$(gh pr view "$pr" --repo "$repo" --json body --jq '.body // ""')"

gh pr merge "$pr" --repo "$repo" --squash --subject "$title" --body "$body"

state="$(field state)"
[ "$state" = MERGED ] || { echo "PR #$pr is $state after merge" >&2; exit 1; }
oid="$(gh pr view "$pr" --repo "$repo" --json mergeCommit --jq .mergeCommit.oid)"
[ "$(gh api "repos/$repo/commits/$oid" --jq '.parents | length')" = 1 ] || { echo "Landed commit $oid is not a squash" >&2; exit 1; }
landed="$(gh api "repos/$repo/commits/$oid" --jq '.commit.message' | head -1)"
[ "$landed" = "$title (#$pr)" ] || { echo "Landed subject is '$landed', expected '$title (#$pr)'" >&2; exit 1; }

git fetch -q origin "$default"
[ "$(git symbolic-ref --short -q HEAD || true)" = "$default" ] || git switch -q "$default"
git pull -q --ff-only origin "$default"
[ "$(git rev-parse HEAD)" = "$oid" ] || { echo "Local $default is $(git rev-parse --short HEAD), not the landed $oid" >&2; exit 1; }
! git show-ref --verify --quiet "refs/heads/$head" || git branch -q -D "$head"
if git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1; then git push -q origin --delete "$head"; fi
! git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1 || { echo "origin still has $head" >&2; exit 1; }
git fetch -q --prune origin
echo "landed $repo#$pr as $(git rev-parse --short "$oid"): $landed"
}
land_evolution_main "$@"; exit $?
