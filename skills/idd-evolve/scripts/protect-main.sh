#!/usr/bin/env bash
set -euo pipefail

# Make GitHub enforce the reviewed-pull-request path onto a repository's default
# branch, or verify that it still does. One ruleset, one repository settings
# shape, no bypass: a direct push, a merge commit, a rebase merge, a force-push,
# or a branch deletion is refused by the provider, not by prose.
#
#   protect-main.sh apply  [OWNER/REPO]   create or update the ruleset and settings
#   protect-main.sh verify [OWNER/REPO]   exit 1 and name every drift from that shape

usage() { echo "usage: protect-main.sh apply|verify [OWNER/REPO]" >&2; exit 64; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage
mode="$1"; repo="${2:-}"
case "$mode" in apply|verify) ;; *) usage;; esac
if [ -z "$repo" ]; then
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
[[ "$repo" == */* ]] || usage

ruleset_name="require-pull-request"
# Expected shapes, as the canonical strings verify compares against.
expected_settings="true false false true PR_TITLE PR_BODY"
expected_ruleset="active | 0 | ~DEFAULT_BRANCH | deletion,non_fast_forward,pull_request,required_linear_history | 0 true true squash"

settings_json='{"allow_squash_merge":true,"allow_merge_commit":false,"allow_rebase_merge":false,"delete_branch_on_merge":true,"squash_merge_commit_title":"PR_TITLE","squash_merge_commit_message":"PR_BODY"}'
ruleset_json='{"name":"'"$ruleset_name"'","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"required_linear_history"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":true,"allowed_merge_methods":["squash"]}}]}'

settings_query='[.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge,.delete_branch_on_merge,.squash_merge_commit_title,.squash_merge_commit_message] | map(tostring) | join(" ")'
ruleset_query='[.enforcement, (.bypass_actors|length|tostring), (.conditions.ref_name.include|join(",")), ([.rules[].type]|sort|join(",")), ((.rules[]|select(.type=="pull_request")|.parameters) as $p | [$p.required_approving_review_count, $p.dismiss_stale_reviews_on_push, $p.required_review_thread_resolution, (($p.allowed_merge_methods // [])|join("+"))] | map(tostring) | join(" "))] | join(" | ")'

ruleset_id() { gh api "repos/$repo/rulesets" --jq ".[] | select(.name==\"$ruleset_name\") | .id"; }

write() { # $1 = method, $2 = path, stdin = JSON body; a refusal names the plan limit on private repositories
  local err
  if ! err="$(gh api --method "$1" "$2" --input - 2>&1 >/dev/null)"; then
    echo "$err" >&2
    if [ "$(gh api "repos/$repo" --jq .visibility)" = private ]; then
      echo "GitHub Free does not enforce rulesets on a private repository; make $repo public or upgrade the plan before protecting it" >&2
    fi
    exit 1
  fi
}

if [ "$mode" = apply ]; then
  printf '%s' "$settings_json" | write PATCH "repos/$repo"
  id="$(ruleset_id)"
  if [ -n "$id" ]; then
    printf '%s' "$ruleset_json" | write PUT "repos/$repo/rulesets/$id"
  else
    printf '%s' "$ruleset_json" | write POST "repos/$repo/rulesets"
  fi
fi

drift=0
settings="$(gh api "repos/$repo" --jq "$settings_query")"
[ "$settings" = "$expected_settings" ] || {
  echo "settings drift: $repo has [$settings], want [$expected_settings] (squash-only, delete on merge, PR title/body)" >&2; drift=1; }
id="$(ruleset_id)"
if [ -z "$id" ]; then
  echo "ruleset drift: $repo has no ruleset named $ruleset_name" >&2; drift=1
else
  ruleset="$(gh api "repos/$repo/rulesets/$id" --jq "$ruleset_query")"
  [ "$ruleset" = "$expected_ruleset" ] || {
    echo "ruleset drift: $repo ruleset $ruleset_name is [$ruleset], want [$expected_ruleset]" >&2; drift=1; }
fi
[ "$drift" -eq 0 ] || { echo "$repo default branch is not protected; run: bash scripts/protect-main.sh apply $repo" >&2; exit 1; }
echo "$repo default branch protected: pull request required, squash only, linear, no force-push, no bypass"
