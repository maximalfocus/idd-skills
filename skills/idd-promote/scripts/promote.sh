#!/usr/bin/env bash
set -euo pipefail

# Promote a repository's integration branch into its release branch on the user's
# explicit instruction: open (or reuse) the one integration-to-release pull
# request, then merge it with a merge commit so the release branch keeps the
# integration branch's ancestry and the two never diverge. Nothing here pushes a
# branch, rewrites history, or merges past a review the provider still blocks.
#
#   promote.sh [--open-only] [OWNER/REPO]

usage() { echo "usage: promote.sh [--open-only] [OWNER/REPO]" >&2; exit 64; }
open_only=false
[ "${1:-}" != --open-only ] || { open_only=true; shift; }
[ "$#" -le 1 ] || usage
repo="${1:-}"
[ -n "$repo" ] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
[[ "$repo" == */* ]] || usage
protect="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../idd-plan/scripts" && pwd)/protect-main.sh"
[ -f "$protect" ] || { echo "Missing sibling idd-plan/scripts/protect-main.sh" >&2; exit 1; }

branches="$(bash "$protect" show "$repo")"
echo "$branches"
integration="$(sed -n 's/^integration=\([^ ]*\) .*/\1/p' <<<"$branches")"
release="${branches##*release=}"
[ "$release" != none ] || {
  echo "$repo integrates on $integration with no release branch; nothing to promote" >&2; exit 1; }
bash "$protect" verify "$repo" >/dev/null || {
  echo "Promotion stops before any mutation: $repo branch protection drifted" >&2; exit 1; }

title="chore(release): promote $integration to $release"
pr="$(gh pr list --repo "$repo" --base "$release" --head "$integration" --state open \
  --json number --jq '.[0].number // empty')"
if [ -z "$pr" ]; then
  ahead="$(gh api "repos/$repo/compare/$release...$integration" --jq .ahead_by)"
  [ "$ahead" != 0 ] || {
    echo "NOTHING to promote: $release already contains $integration"; exit 0; }
  subjects="$(gh api "repos/$repo/compare/$release...$integration" \
    --jq '.commits[] | "- " + (.commit.message | split("\n")[0])')"
  body="$(printf 'Promotes %s commits from %s to %s:\n\n%s' "$ahead" "$integration" "$release" \
    "$subjects")"
  url="$(gh pr create --repo "$repo" --base "$release" --head "$integration" --title "$title" \
    --body "$body")"
  pr="${url##*/}"
  echo "OPENED pr=$pr $url"
fi
[ "$open_only" = false ] || {
  echo "Promotion PR #$pr awaits review; rerun without --open-only"; exit 0; }

field() { gh pr view "$pr" --repo "$repo" --json "$1" --jq ".$1"; }
[ "$(field state)" = OPEN ] || { echo "PR #$pr is not OPEN" >&2; exit 1; }
[ "$(field isDraft)" = false ] || { echo "PR #$pr is a draft" >&2; exit 1; }
[ "$(field title)" = "$title" ] || { echo "PR #$pr title must be '$title'" >&2; exit 1; }
[ "$(field reviewDecision)" != CHANGES_REQUESTED ] || {
  echo "PR #$pr has requested changes" >&2; exit 1; }
merge_state="$(field mergeStateStatus)"
case "$merge_state" in
  CLEAN) ;;
  BLOCKED) echo "PR #$pr is BLOCKED by a repository rule:" \
    "resolve its reviews and threads, then rerun" >&2; exit 1;;
  *) echo "PR #$pr merge state is $merge_state, not CLEAN;" \
    "rerun once GitHub reports it clean" >&2; exit 1;;
esac
head_oid="$(field headRefOid)"
body="$(gh pr view "$pr" --repo "$repo" --json body --jq '.body // ""')"
# Bind the merge to the reviewed head; a later landing on the integration branch waits for the
# next promotion.
gh pr merge "$pr" --repo "$repo" --merge --match-head-commit "$head_oid" --subject "$title (#$pr)" \
  --body "$body"
[ "$(field state)" = MERGED ] || { echo "PR #$pr is not MERGED after merge" >&2; exit 1; }
oid="$(gh pr view "$pr" --repo "$repo" --json mergeCommit --jq '.mergeCommit.oid // ""')"
parents="$(gh api "repos/$repo/commits/$oid" --jq '[.parents[].sha] | join(" ")')"
[ "${parents##* }" = "$head_oid" ] && [ "$parents" != "$head_oid" ] || {
  echo "Promotion commit $oid is not a merge of $integration at $head_oid" >&2; exit 1; }
echo "PROMOTED pr=$pr merge=$oid integration=$integration release=$release subject=$title (#$pr)"
