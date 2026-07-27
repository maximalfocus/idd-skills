#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: land.sh OWNER/REPO ISSUE PR" >&2; exit 64; }
[ "$#" -eq 3 ] || usage
repo="$1"; issue="$2"; pr="$3"
[[ "$issue" =~ ^[0-9]+$ && "$pr" =~ ^[0-9]+$ && "$repo" == */* ]] || usage

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repository" >&2; exit 1; }
cd "$root"
[ -z "$(git status --porcelain)" ] || { echo "Refusing to land with a dirty working tree" >&2; exit 1; }
git remote get-url origin >/dev/null
actual_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[ "$actual_repo" = "$repo" ] || { echo "Checkout is $actual_repo, not $repo" >&2; exit 1; }

default_branch="$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)"
state="$(gh pr view "$pr" --repo "$repo" --json state --jq .state)"
head="$(gh pr view "$pr" --repo "$repo" --json headRefName --jq .headRefName)"
base="$(gh pr view "$pr" --repo "$repo" --json baseRefName --jq .baseRefName)"
[ "$head" != "$base" ] || { echo "Refusing to delete the base branch" >&2; exit 1; }
[ "$base" = "$default_branch" ] || { echo "PR base $base is not default branch $default_branch" >&2; exit 1; }
initial_issue_state="$(gh issue view "$issue" --repo "$repo" --json state --jq .state)"
if [ "$initial_issue_state" = "CLOSED" ] && [ "$state" != "MERGED" ]; then
  echo "Issue is already closed but PR is not merged" >&2; exit 1
fi
[ "$initial_issue_state" = "OPEN" ] || [ "$initial_issue_state" = "CLOSED" ] || {
  echo "Unexpected issue state: $initial_issue_state" >&2; exit 1
}
[ "$(gh pr view "$pr" --repo "$repo" --json isCrossRepository --jq .isCrossRepository)" = false ] || {
  echo "Cross-repository PR branches require manual cleanup" >&2; exit 1;
}

# The post-merge refresh is ff-only. Prove it can succeed before mutating GitHub; otherwise a
# local-only default-branch commit would let the remote merge/issue closure happen and fail cleanup.
git fetch -q origin "$default_branch"
git show-ref --verify --quiet "refs/heads/$default_branch" || {
  echo "Local default branch $default_branch does not exist" >&2; exit 1;
}
git merge-base --is-ancestor "refs/heads/$default_branch" FETCH_HEAD || {
  echo "Local $default_branch cannot fast-forward to origin/$default_branch; reconcile it before landing" >&2
  exit 1
}

if [ "$state" = "OPEN" ]; then
  [ "$(gh pr view "$pr" --repo "$repo" --json isDraft --jq .isDraft)" = false ] || { echo "PR is a draft" >&2; exit 1; }
  review="$(gh pr view "$pr" --repo "$repo" --json reviewDecision --jq '.reviewDecision // ""')"
  [ "$review" != "CHANGES_REQUESTED" ] || { echo "PR has requested changes" >&2; exit 1; }
  mergeable="UNKNOWN"
  for _ in 1 2 3 4 5; do
    mergeable="$(gh pr view "$pr" --repo "$repo" --json mergeable --jq .mergeable)"
    [ "$mergeable" != "UNKNOWN" ] && break
    sleep 2
  done
  [ "$mergeable" = "MERGEABLE" ] || { echo "PR is not mergeable: $mergeable" >&2; exit 1; }

  set +e
  checks="$(gh pr checks "$pr" --repo "$repo" 2>&1)"
  checks_rc=$?
  set -e
  if [ "$checks_rc" -ne 0 ] && ! grep -qiE 'no checks reported|no checks found' <<<"$checks"; then
    printf 'PR checks are not green:\n%s\n' "$checks" >&2
    exit 1
  fi

  gh pr merge "$pr" --repo "$repo" --squash --delete-branch
elif [ "$state" != "MERGED" ]; then
  echo "PR is $state, not open or merged" >&2
  exit 1
fi

state="$(gh pr view "$pr" --repo "$repo" --json state --jq .state)"
[ "$state" = "MERGED" ] || { echo "Merge did not complete" >&2; exit 1; }
merge_oid="$(gh pr view "$pr" --repo "$repo" --json mergeCommit --jq .mergeCommit.oid)"
[ -n "$merge_oid" ] || { echo "Merged PR has no merge commit" >&2; exit 1; }
parent_count="$(gh api "repos/$repo/commits/$merge_oid" --jq '.parents | length')"
[ "$parent_count" = 1 ] || { echo "PR was not squash/rebase merged (merge commit has $parent_count parents)" >&2; exit 1; }

issue_state="$(gh issue view "$issue" --repo "$repo" --json state --jq .state)"
if [ "$issue_state" = "OPEN" ]; then
  gh issue close "$issue" --repo "$repo" --comment "Implemented and squash-merged in PR #$pr."
elif [ "$issue_state" != "CLOSED" ]; then
  echo "Unexpected issue state: $issue_state" >&2
  exit 1
fi

git checkout "$default_branch"
git pull --ff-only origin "$default_branch"
if git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1; then
  git push origin --delete "$head"
fi
if git show-ref --verify --quiet "refs/heads/$head"; then
  git branch -D "$head"
fi
git fetch --prune origin

[ -z "$(git status --porcelain)" ] || { echo "Working tree is dirty after landing" >&2; exit 1; }
[ "$(git branch --show-current)" = "$default_branch" ] || { echo "Not on $default_branch" >&2; exit 1; }
[ "$(gh pr view "$pr" --repo "$repo" --json state --jq .state)" = "MERGED" ] || { echo "PR postcondition failed" >&2; exit 1; }
[ "$(gh issue view "$issue" --repo "$repo" --json state --jq .state)" = "CLOSED" ] || { echo "Issue postcondition failed" >&2; exit 1; }
! git show-ref --verify --quiet "refs/heads/$head" || { echo "Local branch still exists" >&2; exit 1; }
! git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1 || { echo "Remote branch still exists" >&2; exit 1; }

printf 'LANDED issue=%s pr=%s squash=%s base=%s deleted=%s\n' "$issue" "$pr" "$merge_oid" "$default_branch" "$head"
