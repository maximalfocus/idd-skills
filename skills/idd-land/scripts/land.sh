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

# GitHub derives a squash subject from the pull-request title, and the title
# conventions deliberately leave that title untyped. Compose the subject here
# instead, from a type the pull request declares, so the landed commit carries
# its type without the title having to. Validate before mutating anything.
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

# A repository that declares its own type vocabulary owns it. One that declares
# none is not silently constrained to this script's opinion of a good type.
allowed=""
for conventions in AGENTS.md CLAUDE.md; do
  [ -f "$root/$conventions" ] || continue
  allowed="$(awk '
    /^[[:space:]]*Types:/ { collecting = 1; sub(/^[[:space:]]*Types:/, ""); }
    collecting && !/^[[:space:]]*Types:/ && $0 !~ /^[[:space:]]*(`[a-z][a-z0-9]*`[[:space:]]*)+$/ { collecting = 0 }
    collecting { print }
  ' "$root/$conventions" | tr -d '`' | tr -s ' \t' '\n' | grep -E '^[a-z][a-z0-9]*$' || true)"
  [ -n "$allowed" ] && break
done
if [ -n "$allowed" ]; then
  printf '%s\n' "$allowed" | grep -qx -- "$delivery_type" || {
    echo "Delivery-Type '$delivery_type' is not one this repository allows: $(printf '%s' "$allowed" | tr '\n' ' ')" >&2
    exit 1
  }
fi

issue_title="$(gh issue view "$issue" --repo "$repo" --json title --jq .title)"
[ -n "$issue_title" ] || { echo "Issue #$issue has no title" >&2; exit 1; }
title_head="$(printf '%s' "$issue_title" | cut -c1 | tr 'A-Z' 'a-z')"
title_tail="$(printf '%s' "$issue_title" | cut -c2-)"
authored_subject="$delivery_type: $title_head$title_tail"
[ "${#authored_subject}" -le 72 ] || {
  echo "Composed subject is ${#authored_subject} characters, over the 72 budget: $authored_subject" >&2
  echo "Shorten the issue title; landing does not truncate." >&2
  exit 1
}
squash_subject="$authored_subject (#$pr)"

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

  gh pr merge "$pr" --repo "$repo" --squash --delete-branch --subject "$squash_subject"
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

[ -z "$(git status --porcelain)" ] || { echo "Working tree is dirty after landing" >&2; exit 1; }
[ "$(git branch --show-current)" = "$default_branch" ] || { echo "Not on $default_branch" >&2; exit 1; }
[ "$(gh pr view "$pr" --repo "$repo" --json state --jq .state)" = "MERGED" ] || { echo "PR postcondition failed" >&2; exit 1; }
[ "$(gh issue view "$issue" --repo "$repo" --json state --jq .state)" = "CLOSED" ] || { echo "Issue postcondition failed" >&2; exit 1; }
! git show-ref --verify --quiet "refs/heads/$head" || { echo "Local branch still exists" >&2; exit 1; }
! git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1 || { echo "Remote branch still exists" >&2; exit 1; }

printf 'LANDED issue=%s pr=%s squash=%s base=%s deleted=%s subject=%s\n' "$issue" "$pr" "$merge_oid" "$default_branch" "$head" "$squash_subject"
