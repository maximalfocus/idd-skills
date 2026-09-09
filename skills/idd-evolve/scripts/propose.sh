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
[ "$(wc -l < "$message" | tr -d ' ')" -le 1 ] || [ -z "$(sed -n 2p "$message")" ] || {
  echo "Message body must be separated from the subject by one blank line" >&2; exit 1; }

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
! git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 || { echo "Branch already exists on origin: $branch" >&2; exit 1; }
git diff --cached --quiet || { echo "Index already has staged changes; unstage them so only the named paths are committed" >&2; exit 1; }
for path in "${paths[@]}"; do
  [ -n "$(git status --porcelain --untracked-files=all -- "$path")" ] || { echo "No change under $path" >&2; exit 1; }
done

body="$(mktemp)"; trap 'rm -f "$body"' EXIT
tail -n +2 "$message" | sed '/./,$!d' > "$body"

on_error() { echo "propose stopped on $(git symbolic-ref --short -q HEAD || echo 'detached HEAD'); the commit, if made, is only on $branch" >&2; }
trap on_error ERR
git switch -q -c "$branch"
git add -- "${paths[@]}"
git commit -q -F "$message"
git push -q -u origin "$branch"
pr_url="$(gh pr create --repo "$repo" --base "$default" --head "$branch" --title "$subject" --body-file "$body")"
state="$(gh pr view "$branch" --repo "$repo" --json state --jq .state)"
[ "$state" = OPEN ] || { echo "PR for $branch is $state, not OPEN" >&2; exit 1; }
git switch -q "$default"
trap - ERR
echo "$pr_url"
