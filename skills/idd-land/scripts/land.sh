#!/usr/bin/env bash
set -euo pipefail

# The whole sequence is one function so that bash parses it completely before
# executing anything. When the installed skill resolves into the repository being
# landed, the mid-sequence checkout rewrites this file; a script read
# incrementally would then execute the rewritten tail.
land_main() {
usage() { echo "usage: land.sh OWNER/REPO ISSUE PR" >&2; exit 64; }
[ "$#" -eq 3 ] || usage
repo="$1"; issue="$2"; pr="$3"
[[ "$issue" =~ ^[0-9]+$ && "$pr" =~ ^[0-9]+$ && "$repo" == */* ]] || usage

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plan_scripts="$here/../../idd-plan/scripts"
[ -f "$plan_scripts/line-width.sh" ] && [ -f "$plan_scripts/protect-main.sh" ] || {
  echo "Sibling idd-plan scripts are missing: incomplete installation" >&2; exit 1; }
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repository" >&2; exit 1; }
cd "$root"
tree="$(git status --porcelain)" || { echo "Cannot read the working tree state; refusing to land" >&2; exit 1; }
[ -z "$tree" ] || { echo "Refusing to land with a dirty working tree" >&2; exit 1; }
git remote get-url origin >/dev/null
actual_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[ "$actual_repo" = "$repo" ] || { echo "Checkout is $actual_repo, not $repo" >&2; exit 1; }

default_branch="$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)"
state="$(gh pr view "$pr" --repo "$repo" --json state --jq .state)"
head="$(gh pr view "$pr" --repo "$repo" --json headRefName --jq .headRefName)"
base="$(gh pr view "$pr" --repo "$repo" --json baseRefName --jq .baseRefName)"
[ "$head" != "$base" ] || { echo "Refusing to delete the base branch" >&2; exit 1; }
[ "$base" = "$default_branch" ] || { echo "PR base $base is not default branch $default_branch" >&2; exit 1; }
[[ "$head" =~ ^issue/$issue-[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
  echo "PR head $head is not an issue/$issue-<slug> branch (N-3)" >&2; exit 1; }
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

# GitHub derives a squash subject from the pull-request title, which N-2 leaves
# untyped. Compose the subject here instead, from the one N-4 type the pull request
# declares, so the landed commit carries its type without the title having to.
# Validate every shared convention (idd-plan/references/conventions.md) before
# mutating anything.
pr_body="$(gh pr view "$pr" --repo "$repo" --json body --jq '.body // ""')"
declared="$(printf '%s\n' "$pr_body" \
  | sed -n 's/^[[:space:]]*Delivery-Type:[[:space:]]*\([A-Za-z0-9][A-Za-z0-9_-]*\)[[:space:]]*$/\1/p')"
declared_count="$(printf '%s' "$declared" | grep -c . || true)"
[ "$declared_count" -ne 0 ] || {
  echo "PR #$pr declares no 'Delivery-Type: <type>' field; landing cannot compose a typed subject" >&2
  exit 1
}
[ "$declared_count" -eq 1 ] || {
  echo "PR #$pr declares Delivery-Type $declared_count times; exactly one is required" >&2
  exit 1
}
delivery_type="$(printf '%s' "$declared" | head -1)"
[[ "$delivery_type" =~ ^[a-z][a-z0-9]*$ ]] || {
  echo "Delivery-Type '$delivery_type' is not a lowercase type token" >&2; exit 1
}

# Every IDD-managed repository shares one vocabulary, so no repository widens it.
types='feat|fix|docs|test|refactor|perf|chore|build|ci|evolve'
[[ "$delivery_type" =~ ^($types)$ ]] || {
  echo "Delivery-Type '$delivery_type' is not an N-4 type: ${types//|/ }" >&2; exit 1
}

issue_title="$(gh issue view "$issue" --repo "$repo" --json title --jq .title)"
[ -n "$issue_title" ] || { echo "Issue #$issue has no title" >&2; exit 1; }
# The subject form wants a lowercase opening letter, but not at the cost of an
# initialism: READMEs or PRD would land as rEADMEs or pRD, a word nobody wrote.
title_head="$(printf '%s' "$issue_title" | cut -c1)"
case "$issue_title" in
  [[:upper:]][[:upper:]]*) ;;
  *) title_head="$(printf '%s' "$title_head" | tr 'A-Z' 'a-z')";;
esac
title_tail="$(printf '%s' "$issue_title" | cut -c2-)"
authored_subject="$delivery_type: $title_head$title_tail"
[ "${#authored_subject}" -le 72 ] || {
  echo "Composed subject is ${#authored_subject} characters, over the 72 budget: $authored_subject" >&2
  echo "Shorten the issue title; landing does not truncate." >&2
  exit 1
}
squash_subject="$authored_subject (#$pr)"
if [ "$state" = OPEN ]; then
  pr_title="$(gh pr view "$pr" --repo "$repo" --json title --jq .title)"
  [ "$pr_title" = "$issue_title" ] || {
    echo "PR title differs from the issue title (N-2); edit the issue first, then match the PR" >&2
    exit 1
  }
  # Its stderr names any drift and the apply that repairs it; apply changes repository
  # settings, so landing never runs it.
  bash "$plan_scripts/protect-main.sh" verify "$repo" >/dev/null || {
    echo "Landing stops before any mutation; adopt default-branch protection on the user's" \
      "instruction (idd-plan/references/conventions.md, Adopting an existing repository)" >&2
    exit 1
  }
fi

# The post-merge refresh is ff-only. Prove it can succeed before mutating GitHub; otherwise a
# local-only default-branch commit would let the remote merge/issue closure happen and fail cleanup.
git fetch -q origin "$default_branch"
default_oid="$(git rev-parse FETCH_HEAD)"
git show-ref --verify --quiet "refs/heads/$default_branch" || {
  echo "Local default branch $default_branch does not exist" >&2; exit 1;
}
git merge-base --is-ancestor "refs/heads/$default_branch" "$default_oid" || {
  echo "Local $default_branch cannot fast-forward to origin/$default_branch; reconcile it before landing" >&2
  exit 1
}

merged_here=0
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

  # Check the head's added lines, then bind the merge to that head: a later push fails the merge.
  git fetch -q origin "refs/heads/$head"
  head_oid="$(git rev-parse FETCH_HEAD)"
  bash "$plan_scripts/line-width.sh" check "$default_oid" "$head_oid" >/dev/null
  gh pr merge "$pr" --repo "$repo" --squash --delete-branch --match-head-commit "$head_oid" \
    --subject "$squash_subject"
  merged_here=1
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
if [ "$merged_here" = 1 ]; then
  landed_subject="$(gh api "repos/$repo/commits/$merge_oid" --jq '.commit.message' | head -1)"
  [ "$landed_subject" = "$squash_subject" ] || {
    echo "Landed subject is not the composed one:" >&2
    echo "  composed: $squash_subject" >&2
    echo "  landed:   $landed_subject" >&2
    exit 1
  }
fi

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

tree="$(git status --porcelain)" || { echo "Cannot read the working tree state after landing" >&2; exit 1; }
[ -z "$tree" ] || { echo "Working tree is dirty after landing" >&2; exit 1; }
[ "$(git branch --show-current)" = "$default_branch" ] || { echo "Not on $default_branch" >&2; exit 1; }
[ "$(gh pr view "$pr" --repo "$repo" --json state --jq .state)" = "MERGED" ] || { echo "PR postcondition failed" >&2; exit 1; }
[ "$(gh issue view "$issue" --repo "$repo" --json state --jq .state)" = "CLOSED" ] || { echo "Issue postcondition failed" >&2; exit 1; }
! git show-ref --verify --quiet "refs/heads/$head" || { echo "Local branch still exists" >&2; exit 1; }
! git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1 || { echo "Remote branch still exists" >&2; exit 1; }

printf 'LANDED issue=%s pr=%s squash=%s base=%s deleted=%s subject=%s\n' "$issue" "$pr" "$merge_oid" "$default_branch" "$head" "$squash_subject"
}

land_main "$@"; exit $?
