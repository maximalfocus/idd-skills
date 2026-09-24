#!/usr/bin/env bash
set -euo pipefail

# Make GitHub enforce the reviewed-pull-request path onto a repository's default
# branch, or verify that it still does. One ruleset, one repository settings
# shape, no bypass: a direct push, a merge commit, a rebase merge, a force-push,
# or a branch deletion is refused by the provider, not by prose.
#
# The default branch is the integration branch every pull request targets. When
# it is not main and a main branch exists, main is the release branch: a second
# ruleset lets it change only through a merge-commit pull request from the
# integration branch (/idd-promote), so the two never diverge.
#
#   protect-main.sh show      [OWNER/REPO]   print integration=<branch> release=<main|none>
#   protect-main.sh apply     [OWNER/REPO]   create or update the rulesets and settings
#   protect-main.sh verify    [OWNER/REPO]   exit 1 and name every drift from that shape
#   protect-main.sh integrate [OWNER/REPO]   create dev from main, make it default, apply
#   protect-main.sh ensure    [OWNER/REPO]   integrate unless opted out, then print as show
#
# ensure is the first step of every delivery phase. An implementation repository
# integrates on dev whatever main's history; a root AGENTS.md or CLAUDE.md line
# `Integration-branch: main` in the checkout opts out, and a {project}-prd always
# stays single-branch. Integrating retargets open pull requests from main to dev
# and puts this checkout on dev.
#
# GitHub Free enforces rulesets only on public repositories. On a private one,
# apply sets the merge settings and defers the ruleset, and verify passes on the
# settings alone while saying so; once the repository is public, verify fails
# until apply is rerun, which completes the protection.

usage() {
  echo "usage: protect-main.sh show|apply|verify|integrate|ensure [OWNER/REPO]" >&2; exit 64
}
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
mode="$1"; repo="${2:-}"
case "$mode" in show|apply|verify|integrate|ensure) ;; *) usage;; esac
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
[[ "$repo" == */* ]] || usage
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
unprotected() { # apply changes repository settings: name it, runnable from any checkout
  echo "$repo default branch is not protected; on the user's instruction run once:" \
    "bash $self apply $repo" >&2
  exit 1
}
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

refused() { # $1 = gh's error text; a refused ruleset call names the private plan limit
  echo "$1" >&2
  if [ "$(gh api "repos/$repo" --jq .visibility)" = private ]; then
    echo "GitHub Free does not enforce rulesets on a private repository; make $repo public" \
      "or upgrade the plan before protecting it" >&2
  fi
  exit 1
}
ruleset_id() { # $1 = name; GitHub refuses even the read on a private GitHub Free repository
  local out
  out="$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name==\"$1\") | .id" 2>&1)" ||
    refused "$out"
  printf '%s' "$out"
}
write() { # $1 = method, $2 = path, stdin = JSON body
  local err
  err="$(gh api --method "$1" "$2" --input - 2>&1 >/dev/null)" || refused "$err"
}

strategy
if [ "$mode" = show ]; then echo "integration=$integration release=$release"; exit 0; fi
ensured=false
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
  ensured=true; mode=integrate
fi
if [ "$mode" = integrate ]; then
  # Adoption changes the branch every pull request targets: an explicit integrate or ensure only.
  case "$integration" in
    dev) ;;
    main)
      if ! has_branch dev; then
        sha="$(gh api "repos/$repo/git/ref/heads/main" --jq .object.sha)"
        printf '{"ref":"refs/heads/dev","sha":"%s"}' "$sha" | write POST "repos/$repo/git/refs"
      fi
      printf '{"default_branch":"dev"}' | write PATCH "repos/$repo" ;;
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
  mode=apply
fi
default_rules='{"type":"deletion"},{"type":"non_fast_forward"},{"type":"required_linear_history"}'
release_rules='{"type":"deletion"},{"type":"non_fast_forward"}'
pr_rule() { # $1 = the one allowed merge method
  printf '%s' '{"type":"pull_request","parameters":{"required_approving_review_count":0,' \
    '"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,' \
    '"require_last_push_approval":false,"required_review_thread_resolution":true,' \
    '"allowed_merge_methods":["'"$1"'"]}}'
}
ruleset_json() { # $1 = name, $2 = ref include, $3 = rules, $4 = merge method
  printf '{"name":"%s","target":"branch","enforcement":"active","bypass_actors":[],%s,%s}' \
    "$1" '"conditions":{"ref_name":{"include":["'"$2"'"],"exclude":[]}}' \
    '"rules":['"$3,$(pr_rule "$4")"']'
}
# Expected shapes, as the canonical strings verify compares against.
if [ "$release" = none ]; then
  merge_commit=false; shape="squash only, linear"
else
  # The release branch takes merge commits, so main keeps the integration branch's ancestry.
  merge_commit=true
  shape="squash only on $integration; $release by merge-commit pull request only"
fi
expected_settings="true $merge_commit false true PR_TITLE PR_BODY"
settings_json='{"allow_squash_merge":true,"allow_merge_commit":'"$merge_commit"','\
'"allow_rebase_merge":false,"delete_branch_on_merge":true,'\
'"squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}'
rulesets=("require-pull-request")
expected_require_pull_request="branch | active | 0 | ~DEFAULT_BRANCH |  | "\
"deletion,non_fast_forward,pull_request,required_linear_history | 0 true true squash false false"
json_require_pull_request="$(ruleset_json require-pull-request "~DEFAULT_BRANCH" \
  "$default_rules" squash)"
if [ "$release" != none ]; then
  rulesets+=("protect-release")
  expected_protect_release="branch | active | 0 | refs/heads/$release |  | "\
"deletion,non_fast_forward,pull_request | 0 true true merge false false"
  json_protect_release="$(ruleset_json protect-release "refs/heads/$release" \
    "$release_rules" merge)"
fi

settings_query='[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge,'\
'.delete_branch_on_merge,.squash_merge_commit_title,.squash_merge_commit_message]'\
' | map(tostring) | join(" ")'
ruleset_query='[.target, .enforcement, (.bypass_actors|length|tostring),'\
' (.conditions.ref_name.include|join(",")), ((.conditions.ref_name.exclude // [])|join(",")),'\
' ([.rules[].type]|sort|join(",")),'\
' ((.rules[]|select(.type=="pull_request")|.parameters) as $p |'\
' [$p.required_approving_review_count, $p.dismiss_stale_reviews_on_push,'\
' $p.required_review_thread_resolution, (($p.allowed_merge_methods // [])|join("+")),'\
' $p.require_code_owner_review, $p.require_last_push_approval]'\
' | map(tostring) | join(" "))] | join(" | ")'

finish() { # $1 = protection summary; ensure also moves a clean checkout on main to dev
  if [ "$ensured" = false ]; then echo "$1"; exit 0; fi
  echo "$1" >&2
  if [ -n "$top" ] && git -C "$top" fetch -q origin dev 2>/dev/null; then
    git -C "$top" show-ref --verify --quiet refs/heads/dev ||
      git -C "$top" branch -q --track dev origin/dev
    if [ "$(git -C "$top" branch --show-current)" = main ] &&
      [ -z "$(git -C "$top" status --porcelain)" ]; then git -C "$top" switch -q dev; fi
  fi
  echo "integration=$integration release=$release"; exit 0
}

visibility="$(gh api "repos/$repo" --jq .visibility)"

if [ "$mode" = apply ]; then
  printf '%s' "$settings_json" | write PATCH "repos/$repo"
  if [ "$visibility" = private ]; then
    echo "ruleset deferred: $repo is private and GitHub Free enforces rulesets only on" \
      "public repositories; rerun apply once it is public" >&2
  else
    for name in "${rulesets[@]}"; do
      var="json_${name//-/_}"; id="$(ruleset_id "$name")"
      if [ -n "$id" ]; then
        printf '%s' "${!var}" | write PUT "repos/$repo/rulesets/$id"
      else
        printf '%s' "${!var}" | write POST "repos/$repo/rulesets"
      fi
    done
  fi
fi

drift=0
settings="$(gh api "repos/$repo" --jq "$settings_query")"
[ "$settings" = "$expected_settings" ] || {
  echo "settings drift: $repo has [$settings], want [$expected_settings]" \
    "($shape, delete on merge, PR title/body)" >&2; drift=1; }
if [ "$visibility" = private ]; then
  [ "$drift" -eq 0 ] || unprotected
  finish "$repo default branch: $shape settings enforced; ruleset DEFERRED while private"\
" (branch and PR discipline only); rerun apply once public"
fi
for name in "${rulesets[@]}"; do
  var="expected_${name//-/_}"; id="$(ruleset_id "$name")"
  if [ -z "$id" ]; then
    echo "ruleset drift: $repo has no ruleset named $name" >&2; drift=1
  else
    ruleset="$(gh api "repos/$repo/rulesets/$id" --jq "$ruleset_query")"
    [ "$ruleset" = "${!var}" ] || {
      echo "ruleset drift: $repo ruleset $name is [$ruleset], want [${!var}]" \
        "(target | enforcement | bypass count | includes | excludes | rules | approvals" \
        "stale-review-dismissal thread-resolution merge-methods code-owner-review" \
        "last-push-approval)" >&2; drift=1; }
  fi
done
[ "$drift" -eq 0 ] || unprotected
finish "$repo default branch protected: pull request required, $shape, no force-push," \
  "no bypass"
