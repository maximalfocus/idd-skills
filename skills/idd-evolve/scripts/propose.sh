#!/usr/bin/env bash
set -euo pipefail

# Propose one kept evolution as a reviewable pull request. From a checkout whose
# default branch equals origin, commit exactly the named paths on
# evolve/<slug>, push that branch, open the PR whose title is the commit subject
# and whose body is the commit body (the squash merge takes both from the PR),
# then return the checkout to the default branch so the installed, symlinked
# skills keep serving what is merged. Nothing here merges or touches main.
#
#   propose.sh SLUG MESSAGE_FILE PATH...

# The whole sequence is one function so that bash parses it completely before
# executing anything: the mid-sequence branch switch may rewrite this very file
# when the checkout serves the installed skill, and a script read incrementally
# would then execute the rewritten tail.
propose_main() {
usage() { echo "usage: propose.sh SLUG MESSAGE_FILE PATH..." >&2; exit 64; }
[ "$#" -ge 3 ] || usage
slug="$1"; message="$2"; shift 2; paths=("$@")

[[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "Slug must be lowercase kebab-case: $slug" >&2; exit 1; }
branch="evolve/$slug"
[ -s "$message" ] || { echo "Message file is missing or empty: $message" >&2; exit 1; }
subject="$(head -1 "$message")"
types='feat|fix|docs|test|refactor|perf|chore|build|ci|evolve'
[[ "$subject" =~ ^($types)(\([a-z0-9]+(-[a-z0-9]+)*\))?:\ [a-z] ]] || {
  echo "Subject must be '<type>(<scope>)?: <lowercase imperative>' with a listed type (N-4): $subject" >&2; exit 1; }
[ "${#subject}" -le 72 ] || { echo "Subject exceeds 72 characters (N-4): ${#subject}" >&2; exit 1; }
[ -z "$(sed -n 2p "$message")" ] || {
  echo "Message body must be separated from the subject by one blank line" >&2; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repository" >&2; exit 1; }
cd "$root"
git remote get-url origin >/dev/null
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
default="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
current="$(git symbolic-ref --short -q HEAD || true)"
[ "$current" = "$default" ] || { echo "Propose from $default, not from '${current:-a detached HEAD}'" >&2; exit 1; }
git fetch -q origin "$default"
head_sha="$(git rev-parse HEAD)"; origin_sha="$(git rev-parse "origin/$default")"
[ "$head_sha" = "$origin_sha" ] || {
  if git merge-base --is-ancestor "$head_sha" "$origin_sha"; then
    echo "Local $default is behind origin; run: git pull --ff-only" >&2
  else
    echo "Local $default has commits origin lacks; move them onto a branch before proposing" >&2
  fi
  exit 1; }
! git show-ref --verify --quiet "refs/heads/$branch" || { echo "Branch already exists locally: $branch" >&2; exit 1; }
if git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  echo "Branch already exists on origin: $branch" >&2; exit 1
else
  remote_status=$?
  [ "$remote_status" -eq 2 ] || { echo "Cannot verify origin branch $branch (git ls-remote exited $remote_status)" >&2; exit 1; }
fi
git diff --cached --quiet || { echo "Index already has staged changes; unstage them so only the named paths are committed" >&2; exit 1; }
for path in "${paths[@]}"; do
  [ -n "$(git status --porcelain --untracked-files=all -- "$path")" ] || { echo "No change under $path" >&2; exit 1; }
done
# Check the exact tree the commit will record against the shared line width, in a
# scratch index so a refusal leaves the real index and checkout untouched.
scratch="$(mktemp -d)"
width_ok=true
GIT_INDEX_FILE="$scratch/index" git read-tree HEAD
GIT_INDEX_FILE="$scratch/index" git add -- "${paths[@]}"
width_gate="$here/../../idd-plan/scripts/line-width.sh"
GIT_INDEX_FILE="$scratch/index" bash "$width_gate" check HEAD --cached >/dev/null || width_ok=false
rm -rf "$scratch"
[ "$width_ok" = true ] || exit 1

body="$(mktemp)"; created_branch=false
finish_proposal() {
  local status=$?
  if [ "$created_branch" = true ] && [ "$(git symbolic-ref --short -q HEAD || true)" = "$branch" ]; then
    git switch -q "$default" || { echo "Could not return to $default; preserve the worktree and recover manually" >&2; status=1; }
  fi
  rm -f "$body"
  return "$status"
}
trap finish_proposal EXIT
tail -n +3 "$message" > "$body"

on_error() { echo "propose stopped on $(git symbolic-ref --short -q HEAD || echo 'detached HEAD'); the commit, if made, is only on $branch" >&2; }
trap on_error ERR
git switch -q -c "$branch"
created_branch=true
git add -- "${paths[@]}"
git commit -q --cleanup=verbatim -F "$message"
git push -q -u origin "$branch"
pr_url="$(gh pr create --repo "$repo" --base "$default" --head "$branch" --title "$subject" --body-file "$body")"
echo "$pr_url"
state="$(gh pr view "$branch" --repo "$repo" --json state --jq .state)"
[ "$state" = OPEN ] || { echo "PR for $branch is $state, not OPEN" >&2; exit 1; }
git switch -q "$default"
trap - ERR
}
propose_main "$@"; exit $?
