#!/usr/bin/env bash
set -euo pipefail

# Name, and on first use set up, the branch every pull request of a repository
# targets. Without local naming, the default branch is integration; when it is not main and
# a main branch exists, main is the release branch, which changes only through
# /idd-promote's merge-commit pull request from the integration branch.
#
# No branch protection is applied, required, or checked: the user's repositories
# have none (their decision, 2026-10-07). The reviewed squash-merged pull request
# is practice the phases follow, not a provider rule.
#
#   integration-branch.sh show      [OWNER/REPO]   print integration=<branch> release=<main|none>
#   integration-branch.sh integrate [OWNER/REPO]   create dev from main and make it default
#   integration-branch.sh ensure    [OWNER/REPO]   integrate unless opted out, then print as show
#
# ensure is the first step of every delivery phase. An implementation repository
# integrates on dev whatever main's history; a root AGENTS.md or CLAUDE.md line
# `Integration-branch: main` in the checkout opts out, and a {project}-prd always
# stays single-branch. Integrating retargets open pull requests from main to dev;
# ensure also switches a clean checkout on main to dev. Both modes retry retargeting
# on every run; ensure retries the checkout work even when dev is already default.
#
# A checkout of a repository IDD may not reshape names its integration branch in its
# own git config instead: git config --local idd.integrationBranch <branch>. Every
# mode run there then only reads: show and ensure print that branch with release=none.
# IDD names no release branch and promotes nothing. Integrate refuses; no dev branch,
# default branch, merge setting, pull-request base, or checked-out branch is changed.

usage() {
  echo "usage: integration-branch.sh show|integrate|ensure [OWNER/REPO]" >&2; exit 64
}
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
mode="$1"; repo="${2:-}"
case "$mode" in show|integrate|ensure) ;; *) usage;; esac
has_branch() { # $1 = branch; a failed lookup other than not-found is not absence
  local err
  err="$(gh api "repos/$repo/branches/$1" --jq .name 2>&1 >/dev/null)" && return 0
  case "$err" in *"HTTP 404"*) return 1;; esac
  echo "$err" >&2; exit 1
}
strategy() { # sets integration and release from the live repository
  integration="$(gh api "repos/$repo" --jq .default_branch)"
  release=none
  if [ "$integration" != main ] && has_branch main; then release=main; fi
}
write() { # $1 = method, $2 = path, stdin = JSON body
  local err
  err="$(gh api --method "$1" "$2" --input - 2>&1 >/dev/null)" || { echo "$err" >&2; exit 1; }
}

# Local config also belongs to bare repositories; worktree discovery is not a key read.
named=""; named_rc=1
if discovery="$(LC_ALL=C git rev-parse --git-dir 2>&1)"; then
  named_rc=0
  # The sentinel preserves value newlines; remove only Git's one output newline.
  named="$(git config --local --get idd.integrationBranch; rc=$?; printf .; exit "$rc")" ||
    named_rc=$?
  named="${named%.}"; named="${named%$'\n'}"
else
  case "$discovery" in
    "fatal: not a git repository (or any "*) ;;
    *) echo "Cannot discover the git repository: $discovery" >&2; exit 1;;
  esac
fi
# A failed read is not an unset key: it must never fall through to integrating.
[ "$named_rc" -le 1 ] || { echo "Cannot read idd.integrationBranch" >&2; exit 1; }
if [ "$named_rc" = 0 ]; then
  [ -n "$named" ] || {
    echo "idd.integrationBranch names '$named', a branch $repo does not have" >&2; exit 1; }
  # Keep the API path, output fields, and Git arguments literal and unambiguous.
  export LC_ALL=C
  [[ "$named" =~ ^[a-zA-Z0-9_][a-zA-Z0-9._/-]*$ ]] &&
    git check-ref-format --branch "$named" >/dev/null 2>&1 || {
      echo "Unsafe idd.integrationBranch: '$named'" >&2; exit 1; }
fi
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
[[ "$repo" == */* ]] || usage
if [ "$named_rc" = 0 ]; then
  [ "$mode" != integrate ] || {
    echo "This repository names its integration branch ($named): integrate refuses" >&2; exit 1; }
  [[ "$repo" != *-prd ]] || {
    echo "A -prd repository stays single-branch: unset idd.integrationBranch" >&2; exit 1; }
  has_branch "$named" || {
    echo "idd.integrationBranch names '$named', a branch $repo does not have" >&2; exit 1; }
  echo "integration=$named release=none"; exit 0
fi
strategy
if [ "$mode" = show ]; then echo "integration=$integration release=$release"; exit 0; fi
ensured=false; top=""
if [ "$mode" = ensure ]; then
  want=dev
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    instructions=""
    for file in "$top/AGENTS.md" "$top/CLAUDE.md"; do
      if [ -e "$file" ] || [ -L "$file" ]; then
        content="$(cat "$file")"
        instructions+="$content"$'\n'
      fi
    done
    line="$(awk '/^Integration-branch:/ { print; exit }' <<<"$instructions")"
    [ -z "$line" ] || want="$(awk '{print $2}' <<<"$line" | tr -d '`')"
  fi
  case "$want" in
    dev|main) ;;
    *) echo "Integration-branch must be dev or main, not '$want'" >&2; exit 1;;
  esac
  [[ "$repo" != *-prd ]] || want=main
  if [ "$want" = main ]; then
    echo "integration=$integration release=$release"; exit 0
  fi
  ensured=true
fi
# Adoption changes the branch every pull request targets: an explicit integrate or ensure only.
case "$integration" in
  dev) ;;
  main)
    if ! has_branch dev; then
      sha="$(gh api "repos/$repo/git/ref/heads/main" --jq .object.sha)"
      printf '{"ref":"refs/heads/dev","sha":"%s"}' "$sha" | write POST "repos/$repo/git/refs"
    fi
    # Promotion merges dev into main with a merge commit, so the repository must allow one.
    printf '{"default_branch":"dev","allow_merge_commit":true}' | write PATCH "repos/$repo" ;;
  *) echo "integrate expects default branch main or dev; $repo defaults to $integration" >&2
    exit 1;;
esac
strategy
[ "$integration $release" = "dev main" ] || {
  echo "integrate read back integration=$integration release=$release, not dev and main" >&2
  exit 1; }
# Open work keeps flowing to the integration branch, never straight to the release branch.
prs="$(gh pr list --repo "$repo" --base main --state open --json number,headRefName \
  --jq '.[] | select(.headRefName != "dev") | .number')"
for pr in $prs; do
  gh pr edit "$pr" --repo "$repo" --base dev >/dev/null
  echo "retargeted $repo#$pr from main to dev" >&2
done
summary="$repo integrates on dev; main is the release branch"
if [ "$ensured" = false ]; then echo "$summary"; exit 0; fi
# ensure also moves a clean checkout on main to dev.
echo "$summary" >&2
if [ -n "$top" ]; then
  git -C "$top" fetch -q origin dev
  git -C "$top" show-ref --verify --quiet refs/heads/dev ||
    git -C "$top" branch -q --track dev origin/dev
  current="$(git -C "$top" branch --show-current)"
  status="$(git -C "$top" status --porcelain)"
  if [ "$current" = main ] && [ -z "$status" ]; then git -C "$top" switch -q dev; fi
fi
echo "integration=$integration release=$release"
