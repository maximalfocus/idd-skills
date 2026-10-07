#!/usr/bin/env bash
set -euo pipefail

# Name, and on first use set up, the branch every pull request of a repository
# targets. The default branch is the integration branch; when it is not main and
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
# stays single-branch. Integrating retargets open pull requests from main to dev
# and puts this checkout on dev.

usage() {
  echo "usage: integration-branch.sh show|integrate|ensure [OWNER/REPO]" >&2; exit 64
}
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
mode="$1"; repo="${2:-}"
case "$mode" in show|integrate|ensure) ;; *) usage;; esac
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
[[ "$repo" == */* ]] || usage
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

strategy
if [ "$mode" = show ]; then echo "integration=$integration release=$release"; exit 0; fi
ensured=false; top=""
if [ "$mode" = ensure ]; then
  want=dev
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then
    line="$(cat "$top/AGENTS.md" "$top/CLAUDE.md" 2>/dev/null |
      grep -m1 '^Integration-branch:' || true)"
    [ -z "$line" ] || want="$(awk '{print $2}' <<<"$line" | tr -d '`')"
  fi
  case "$want" in
    dev|main) ;;
    *) echo "Integration-branch must be dev or main, not '$want'" >&2; exit 1;;
  esac
  [[ "$repo" != *-prd ]] || want=main
  if [ "$want" = main ] || [ "$integration $release" = "dev main" ]; then
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
for pr in $(gh pr list --repo "$repo" --base main --state open --json number,headRefName \
  --jq '.[] | select(.headRefName != "dev") | .number'); do
  gh pr edit "$pr" --repo "$repo" --base dev >/dev/null
  echo "retargeted $repo#$pr from main to dev" >&2
done
summary="$repo integrates on dev; main is the release branch"
if [ "$ensured" = false ]; then echo "$summary"; exit 0; fi
# ensure also moves a clean checkout on main to dev.
echo "$summary" >&2
if [ -n "$top" ] && git -C "$top" fetch -q origin dev 2>/dev/null; then
  git -C "$top" show-ref --verify --quiet refs/heads/dev ||
    git -C "$top" branch -q --track dev origin/dev
  if [ "$(git -C "$top" branch --show-current)" = main ] &&
    [ -z "$(git -C "$top" status --porcelain)" ]; then git -C "$top" switch -q dev; fi
fi
echo "integration=$integration release=$release"
