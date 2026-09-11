#!/usr/bin/env bash
set -euo pipefail

# Route PRD tracker changes through one batched pull request. The PRD default
# branch changes only by a squash merge of that batch at a milestone, and the
# pre-push guard installed here refuses a direct push to it from this clone.
#
#   progress-pr.sh sync  PRD_PATH                  guard; check out the open batch, else default
#   progress-pr.sh push  PRD_PATH SUBJECT PATH...  commit PATHs to the batch, opening it if none
#   progress-pr.sh merge PRD_PATH SUBJECT          squash-merge the open batch, return to default
#
# sync prints branch= and pr=: the checked-out tracker is the current one to read
# and edit. Nothing here force-pushes content.

usage() { echo "usage: progress-pr.sh sync PRD_PATH | push PRD_PATH SUBJECT PATH... | merge PRD_PATH SUBJECT" >&2; exit 64; }
[ "$#" -ge 2 ] || usage
mode="$1"; prd="$2"; shift 2
case "$mode" in
  sync) [ "$#" -eq 0 ] || usage;;
  push) [ "$#" -ge 2 ] || usage;;
  merge) [ "$#" -eq 1 ] || usage;;
  *) usage;;
esac
[ -d "$prd" ] || { echo "Missing PRD checkout: $prd" >&2; exit 1; }
root="$(git -C "$prd" rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a git repository: $prd" >&2; exit 1; }
cd "$root"
tree="$(git status --porcelain --untracked-files=all)" || { echo "Cannot read the working tree state" >&2; exit 1; }
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
default="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
[[ "$repo" == *-prd ]] || { echo "$repo is not a {project}-prd repository" >&2; exit 1; }

check_subject() {
  [[ "$1" =~ ^progress:\ [a-z0-9] ]] || { echo "Subject must be 'progress: <lowercase summary>': $1" >&2; exit 1; }
}
clean() { [ -z "$tree" ] || { echo "Refusing with a dirty PRD tree" >&2; exit 1; }; }

guard() { # install the default-branch pre-push refusal, never over someone else's hook
  local hooks hook
  hooks="$(git rev-parse --git-path hooks)"; hook="$hooks/pre-push"
  if [ -e "$hook" ] && ! grep -q 'idd-progress-guard' "$hook"; then
    echo "An existing pre-push hook was left in place; the $default guard is not installed" >&2
    return 0
  fi
  mkdir -p "$hooks"
  cat > "$hook" <<EOF
#!/bin/sh
# idd-progress-guard: $default in this PRD repository changes only through a pull request.
while read -r _ _ remote_ref _; do
  if [ "\$remote_ref" = "refs/heads/$default" ]; then
    echo "refused: $default changes only through a pull request (idd-plan progress-pr.sh)" >&2
    exit 1
  fi
done
exit 0
EOF
  chmod +x "$hook"
}

batch() { # "<number> <branch>" of the one open same-repository progress PR; nothing when none
  local out count
  out="$(gh pr list --repo "$repo" --state open --base "$default" --json number,headRefName,isCrossRepository \
    --jq '.[] | select((.isCrossRepository | not) and (.headRefName | startswith("progress/"))) | "\(.number) \(.headRefName)"')"
  count="$(printf '%s\n' "$out" | grep -c . || true)"
  [ "$count" -le 1 ] || { echo "More than one open progress batch in $repo: $(printf '%s' "$out" | tr '\n' ' ')" >&2; exit 1; }
  printf '%s' "$out"
}

checkout() { # $1 = branch: check it out at origin's tip, refusing local commits origin lacks
  local b="$1"
  git fetch -q --prune origin
  git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null || { echo "origin has no $b" >&2; exit 1; }
  if git show-ref --verify --quiet "refs/heads/$b"; then
    git merge-base --is-ancestor "refs/heads/$b" "refs/remotes/origin/$b" || {
      echo "Local $b has commits origin lacks; publish or remove them first" >&2; exit 1; }
    [ "$(git symbolic-ref --short -q HEAD || true)" = "$b" ] || git switch -q "$b"
    git merge -q --ff-only "origin/$b"
  else
    git switch -q -c "$b" --track "origin/$b"
  fi
}

if [ "$mode" = sync ]; then
  clean; guard
  b="$(batch)"
  if [ -n "$b" ]; then checkout "${b#* }"; else checkout "$default"; fi
  echo "branch=$(git symbolic-ref --short HEAD)"
  echo "pr=${b%% *}"
  exit 0
fi

if [ "$mode" = push ]; then
  subject="$1"; shift; paths=("$@")
  check_subject "$subject"; guard
  excludes=()
  for path in "${paths[@]}"; do
    [ -n "$(git status --porcelain --untracked-files=all -- "$path")" ] || { echo "No change under $path" >&2; exit 1; }
    excludes+=(":(exclude)$path")
  done
  [ -z "$(git status --porcelain --untracked-files=all -- . "${excludes[@]}")" ] || {
    echo "Changes outside the named paths; a progress batch carries only tracker changes" >&2; exit 1; }
  git fetch -q --prune origin
  current="$(git symbolic-ref --short -q HEAD || true)"
  b="$(batch)"
  if [ -n "$b" ]; then
    branch="${b#* }"
    [ "$current" = "$branch" ] || {
      echo "The open batch is $branch but the checkout is on '${current:-a detached HEAD}'; run sync first" >&2; exit 1; }
    git merge-base --is-ancestor "origin/$branch" HEAD || { echo "$branch is behind origin; run sync first" >&2; exit 1; }
  else
    [ "$current" = "$default" ] || {
      echo "No batch is open; edit on $default after sync, not on '${current:-a detached HEAD}'" >&2; exit 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$default")" ] || {
      echo "Local $default differs from origin; run sync first" >&2; exit 1; }
    branch="progress/$(date -u +%Y%m%d-%H%M%S)"
    git switch -q -c "$branch"
  fi
  git add -- "${paths[@]}"
  git commit -q -m "$subject"
  git push -q -u origin "$branch"
  if [ -z "$b" ]; then
    gh pr create --repo "$repo" --base "$default" --head "$branch" --title "progress: batch tracker reconciliation" \
      --body "Tracker reconciliations batched for review; squash-merged at the next milestone." >/dev/null
    b="$(batch)"
    [ "${b#* }" = "$branch" ] || { echo "No open batch pull request reads back for $branch" >&2; exit 1; }
  fi
  echo "branch=$branch"
  echo "pr=${b%% *}"
  echo "commit=$(git rev-parse HEAD)"
  exit 0
fi

subject="$1"
check_subject "$subject"; clean; guard
b="$(batch)"
if [ -z "$b" ]; then
  checkout "$default"
  echo "no open progress batch; $default at $(git rev-parse --short HEAD)"
  exit 0
fi
pr="${b%% *}"; branch="${b#* }"
field() { gh pr view "$pr" --repo "$repo" --json "$1" --jq ".$1"; }
[ "$(field isDraft)" = false ] || { echo "Batch #$pr is a draft" >&2; exit 1; }
[ "$(field reviewDecision)" != CHANGES_REQUESTED ] || { echo "Batch #$pr has requested changes" >&2; exit 1; }
unresolved="$(gh api graphql -F owner="${repo%%/*}" -F name="${repo#*/}" -F number="$pr" \
  -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved}}}}}' \
  --jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved | not)] | length')"
[ "$unresolved" = 0 ] || { echo "Batch #$pr has $unresolved unresolved review thread(s)" >&2; exit 1; }
merge_state="$(field mergeStateStatus)"
[ "$merge_state" = CLEAN ] || { echo "Batch #$pr merge state is $merge_state, not CLEAN" >&2; exit 1; }
head_oid="$(field headRefOid)"
git fetch -q --prune origin
local_oid=""
if git show-ref --verify --quiet "refs/heads/$branch"; then
  local_oid="$(git rev-parse "refs/heads/$branch")"
  git merge-base --is-ancestor "$local_oid" "$head_oid" || {
    echo "Local $branch has commits absent from batch #$pr; publish or remove them first" >&2; exit 1; }
fi
body="$(git log --reverse --format='- %s' "origin/$default..$head_oid")"
landed="$subject (#$pr)"
# Bind the merge to the reviewed head: a push in between fails the merge instead of landing unseen.
gh pr merge "$pr" --repo "$repo" --squash --match-head-commit "$head_oid" --subject "$landed" --body "$body"
[ "$(field state)" = MERGED ] || { echo "Batch #$pr is not MERGED after the merge" >&2; exit 1; }
oid="$(gh pr view "$pr" --repo "$repo" --json mergeCommit --jq '.mergeCommit.oid // ""')"
[ -n "$oid" ] || { echo "Batch #$pr is MERGED but GitHub reports no merge commit" >&2; exit 1; }
[ "$(gh api "repos/$repo/commits/$oid" --jq '.parents | length')" = 1 ] || { echo "Merged $oid is not a squash" >&2; exit 1; }
[ "$(gh api "repos/$repo/commits/$oid" --jq '.commit.message' | sed -n 1p)" = "$landed" ] || {
  echo "Merged $oid does not carry the subject '$landed'" >&2; exit 1; }
git fetch -q origin "$default"
[ "$(git symbolic-ref --short -q HEAD || true)" = "$default" ] || git switch -q "$default"
git merge -q --ff-only "origin/$default"
git merge-base --is-ancestor "$oid" HEAD || { echo "Local $default does not contain the merged $oid" >&2; exit 1; }
if [ -n "$local_oid" ]; then
  git update-ref -d "refs/heads/$branch" "$local_oid" 2>/dev/null || {
    echo "Local $branch moved while merging; left in place" >&2; exit 1; }
fi
tip="$(git ls-remote --heads origin "$branch")"; tip="${tip%%[[:space:]]*}"
if [ -n "$tip" ]; then
  [ "$tip" = "$head_oid" ] || { echo "origin/$branch is at $tip, not the merged head; left in place" >&2; exit 1; }
  # The lease deletes only the merged head; a branch advanced since is someone's unmerged work.
  git push -q origin --force-with-lease="refs/heads/$branch:$head_oid" ":refs/heads/$branch"
fi
git fetch -q --prune origin
echo "merged=$oid"
echo "subject=$landed"
