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
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -d "$prd" ] || { echo "Missing PRD checkout: $prd" >&2; exit 1; }
root="$(git -C "$prd" rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a git repository: $prd" >&2; exit 1; }
cd "$root"
tree="$(git status --porcelain --untracked-files=all)" || { echo "Cannot read the working tree state" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "Missing dependency: jq; install jq before retrying" >&2; exit 1; }
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
default="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
[[ "$repo" == *-prd ]] || { echo "$repo is not a {project}-prd repository" >&2; exit 1; }

check_subject() { # N-4 in idd-plan/references/conventions.md
  [[ "$1" =~ ^docs\(progress\):\ [a-z0-9] ]] && [ "${#1}" -le 72 ] || {
    echo "Subject must be 'docs(progress): <lowercase summary>' within 72 characters (N-4): $1" >&2
    exit 1
  }
}
clean() { [ -z "$tree" ] || { echo "Refusing with a dirty PRD tree" >&2; exit 1; }; }

guard() { # never write into configured/shared locations or replace an existing hook
  local hooks hook candidate
  if git config --get core.hooksPath >/dev/null; then
    echo "warning: guard NOT installed: configured core.hooksPath left untouched" >&2
    return 0
  fi
  hooks="$(git rev-parse --git-common-dir)/hooks"; hook="$hooks/pre-push"
  [ ! -L "$hooks" ] && [ ! -L "$hook" ] || {
    echo "warning: guard NOT installed: symlinked hooks left untouched" >&2; return 0; }
  candidate="$(mktemp)"
  cat > "$candidate" <<EOF
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
  if [ -e "$hook" ]; then
    if [ -f "$hook" ] && [ -x "$hook" ] && cmp -s "$candidate" "$hook"; then rm "$candidate"; return; fi
    rm "$candidate"
    echo "warning: guard NOT installed: existing pre-push hook left untouched" >&2
    return 0
  fi
  mkdir -p "$hooks"
  chmod +x "$candidate"
  # noclobber also protects a hook installed concurrently.
  ( set -C; cat "$candidate" > "$hook" ) || { rm "$candidate"; exit 1; }
  rm "$candidate"; chmod +x "$hook"
}

batch() { # enumerate every open PR, including batches beyond the first provider page
  local pages out count
  pages="$(gh api --method GET "repos/$repo/pulls" -f state=open -f base="$default" -f per_page=100 --paginate --slurp)" || {
    echo "Cannot list progress batches; retry after the provider lookup succeeds" >&2; return 1; }
  out="$(jq -er --arg repo "$repo" '
    if type != "array" or length == 0 or any(.[]; type != "array") then error("invalid PR pages") else . end |
    [ .[][] | if (.number | type) != "number" or (.head.ref | type) != "string"
      or (.head.repo.full_name | type) != "string" then error("invalid PR") else . end |
      select(.head.repo.full_name == $repo and (.head.ref | startswith("progress/"))) |
      "\(.number) \(.head.ref)" ] | join("\n")' <<<"$pages")" || {
    echo "Invalid progress-batch response; retry the provider lookup" >&2; return 1; }
  count="$(printf '%s\n' "$out" | grep -c . || true)"
  [ "$count" -le 1 ] || { echo "More than one open progress batch in $repo: $(printf '%s' "$out" | tr '\n' ' '); move the commits onto one batch, close the others, then retry" >&2; return 1; }
  printf '%s' "$out"
}

tracker_path() { [[ "$1" = PROGRESS.md || "$1" =~ ^contexts/[a-z0-9]+(-[a-z0-9]+)*/PROGRESS\.md$ ]]; }
tracker_names() {
  local paths="$1" path
  while IFS= read -r path; do
    [ -z "$path" ] || tracker_path "$path" || {
      echo "Non-tracker path in batch: $path; restore it before retrying" >&2; return 1; }
  done <<<"$paths"
}
tracker_diff() {
  local paths
  paths="$(git diff --name-only --no-renames "$@")" || return 1
  tracker_names "$paths"
}
tracker_batch() {
  # An older reviewed head contributes only its diff from the common base, not the
  # newer default's requirements. Remerge diffs expose authored merge resolutions.
  # Git does not generate remerge diffs for octopus merges, so refuse those explicitly.
  [ -z "$(git rev-list --min-parents=3 "origin/$default..$1")" ] || {
    echo "Unsupported octopus merge in batch; preserve its work and rebuild it as ordinary tracker commits" >&2; return 1; }
  tracker_diff "origin/$default...$1" || return 1
  local paths
  paths="$(git log --remerge-diff --format= --name-only --no-renames "origin/$default..$1")" || return 1
  tracker_names "$paths"
}
fresh_batch() {
  git merge-base --is-ancestor "origin/$default" "$1" || {
    echo "Batch lacks origin/$default; preserve tracker edits and run sync before retrying push" >&2
    exit 1
  }
  tracker_batch "$1"
}
only_base_merges() { # extra local work must be reproducible merges of the default branch
  local commits oid parents merged_tree
  commits="$(git rev-list "$1" --not "$2" "origin/$default")" || return 1
  for oid in $commits; do
    parents=( $(git show -s --format=%P "$oid") )
    [ "${#parents[@]}" = 2 ] || return 1
    git merge-base --is-ancestor "${parents[1]}" "origin/$default" || return 1
    merged_tree="$(git merge-tree --write-tree --no-messages "${parents[0]}" "${parents[1]}")" || return 1
    [ "$merged_tree" = "$(git rev-parse "$oid^{tree}")" ] || return 1
  done
}
no_orphans() { # retire exact merged heads; optional resume mode preserves unexplained refs
  local refs pages merged ref oid branch known unknown=""
  refs="$(git for-each-ref --format='%(refname) %(objectname)' refs/heads/progress/ refs/remotes/origin/progress/)"
  [ -n "$refs" ] || return 0
  pages="$(gh api --method GET "repos/$repo/pulls" -f state=closed -f base="$default" -f per_page=100 --paginate --slurp)" || {
    echo "Cannot inspect orphan batch PRs; retry the provider lookup" >&2; exit 1; }
  merged="$(jq -er --arg repo "$repo" --arg base "$default" '
    if type != "array" or length == 0 or any(.[]; type != "array") then error("invalid PR pages") else . end |
    [.[][] | select(.merged_at != null and .head.repo.full_name == $repo and .base.ref == $base) |
      if (.head.ref | type) != "string" or (.head.sha | test("^[0-9a-f]{40}$") | not)
      then error("invalid merged head") else "\(.head.ref) \(.head.sha)" end] | join("\n")' <<<"$pages")" || {
    echo "Invalid orphan PR evidence; retry the provider lookup" >&2; exit 1; }
  while read -r ref oid; do
    branch="${ref#refs/heads/}"; branch="${branch#refs/remotes/origin/}"
    known="$(printf '%s\n' "$merged" | grep -Fx -- "$branch $oid" || true)"
    if [ -z "$known" ]; then unknown="$unknown $ref"; continue; fi
    if [[ "$ref" == refs/heads/* ]]; then
      if [ "$(git symbolic-ref -q HEAD || true)" = "$ref" ]; then
        git switch -q --detach "origin/$default" || {
          echo "Preserve local tracker edits, then run sync to retire merged $branch" >&2; exit 1; }
      fi
      git update-ref -d "$ref" "$oid" || { echo "$branch moved; left in place, retry sync" >&2; exit 1; }
    elif [ "$mode" != sync ]; then
      git push -q origin --force-with-lease="refs/heads/$branch:$oid" ":refs/heads/$branch" || {
        echo "Cannot retire merged $branch; inspect its current tip and retry $mode" >&2; exit 1; }
    fi
  done <<<"$refs"
  git fetch -q --prune origin
  [ -z "$unknown" ] || [ "${1:-}" = resume ] || {
    echo "Progress branches exist without an open PR:$unknown; switch to the intended batch and retry push to resume; inspect unexplained tips before deleting them" >&2
    exit 1
  }
}
merge_default() {
  local before branch conflict=false
  before="$(git rev-parse HEAD)"; branch="$(git symbolic-ref --short HEAD)"
  # Explicit options keep ff-only, squash, signing, autostash and branch options
  # from changing this mechanical import into another operation.
  if ! git -c "branch.$branch.mergeOptions=" -c rerere.enabled=false merge -q --no-edit \
    --ff --no-squash --commit --no-autostash --no-gpg-sign --no-verify-signatures -s ort "origin/$default"; then
    [ -z "$(git ls-files -u)" ] || conflict=true
    if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
      conflict=true
      git merge --abort || { echo "Merge cleanup failed; preserve work and abort the merge before retrying sync" >&2; exit 1; }
    fi
    [ "$(git rev-parse HEAD)" = "$before" ] || {
      echo "Merge failed after HEAD moved; preserve work and inspect the new commits before retrying sync" >&2; exit 1; }
    git restore --source="$before" --staged --worktree -- .
    [ -z "$(git status --porcelain --untracked-files=all)" ] || {
      echo "Merge cleanup left generated files; preserve them outside the checkout before retrying sync" >&2; exit 1; }
    if [ "$conflict" = true ]; then
      echo "Cannot merge origin/$default into the batch: merge conflict aborted; resolve it on a branch through a pull request, then retry sync" >&2
    else
      echo "Cannot merge origin/$default into the batch: merge operation failed without conflict; checkout restored, fix the reported Git error and retry sync" >&2
    fi
    exit 1
  fi
}

checkout() { # permit only verified local default-import merges beyond origin
  local b="$1" local_oid expected_oid
  git fetch -q --prune origin
  git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null || { echo "origin has no $b" >&2; exit 1; }
  expected_oid="$(git rev-parse "origin/$b")"
  if git show-ref --verify --quiet "refs/heads/$b"; then
    local_oid="$(git rev-parse "refs/heads/$b")"
    if ! git merge-base --is-ancestor "$local_oid" "origin/$b"; then
      if [ "$b" = "$default" ]; then
        echo "Local $default has commits origin lacks; move them onto a branch and open a pull request" >&2; exit 1
      fi
      only_base_merges "$local_oid" "origin/$b" || {
        echo "Local $b has unpublished tracker work or unverified merges; publish it with push before retrying sync" >&2; exit 1; }
      if ! git merge-base --is-ancestor "origin/$b" "$local_oid"; then
        # Rebuild only proven mechanical merges when another actor advanced the batch.
        git switch -q --detach "origin/$b"
        git update-ref "refs/heads/$b" "$(git rev-parse "origin/$b")" "$local_oid"
      else expected_oid="$local_oid"; fi
    fi
    if [ "$b" = "$default" ] && [ "$(git symbolic-ref --short -q HEAD || true)" != "$b" ]; then
      # Fast-forward the target ref before switching so carried tracker edits do not
      # cross an obsolete default tree after retiring the checked-out merged batch.
      git update-ref "refs/heads/$b" "$(git rev-parse "origin/$b")" "$local_oid"
    fi
    [ "$(git symbolic-ref --short -q HEAD || true)" = "$b" ] || git switch -q "$b"
    git -c "branch.$b.mergeOptions=" merge -q --ff-only --no-squash --no-autostash \
      --no-gpg-sign --no-verify-signatures "$expected_oid"
  else
    git switch -q -c "$b" --track "origin/$b"
  fi
  [ "$(git rev-parse HEAD)" = "$expected_oid" ] || {
    echo "Checkout did not reach $expected_oid; preserve work, inspect $b, then retry sync" >&2
    exit 1
  }
}

if [ "$mode" = sync ]; then
  clean; guard
  git fetch -q --prune origin
  b="$(batch)"
  if [ -n "$b" ]; then
    tracker_batch "origin/${b#* }"; checkout "${b#* }"
    merge_default; fresh_batch HEAD
  else no_orphans; checkout "$default"; fi
  tree="$(git status --porcelain --untracked-files=all)" || {
    echo "Cannot verify the synced tree; inspect Git errors and retry sync" >&2; exit 1; }
  [ -z "$tree" ] || {
    echo "Sync left a dirty tree; preserve generated changes and inspect Git hooks before retrying" >&2
    exit 1
  }
  echo "branch=$(git symbolic-ref --short HEAD)"
  echo "pr=${b%% *}"
  exit 0
fi

if [ "$mode" = push ]; then
  [[ "${PROGRESS_PR_RETRY_DELAY:-2}" =~ ^[0-5]$ ]] || {
    echo "PROGRESS_PR_RETRY_DELAY must be 0..5 seconds" >&2; exit 1; }
  subject="$1"; shift; paths=("$@")
  check_subject "$subject"; guard
  excludes=()
  for path in "${paths[@]}"; do
    tracker_path "$path" || { echo "Not a literal tracker path: $path" >&2; exit 1; }
    excludes+=(":(exclude)$path")
  done
  [ -z "$(git status --porcelain --untracked-files=all -- . "${excludes[@]}")" ] || {
    echo "Changes outside the named paths; a progress batch carries only tracker changes" >&2; exit 1; }
  git fetch -q --prune origin
  current="$(git symbolic-ref --short -q HEAD || true)"
  b="$(batch)"
  if [ -z "$b" ]; then
    no_orphans resume
    current="$(git symbolic-ref --short -q HEAD || true)"
    [ -n "$current" ] || { checkout "$default"; current="$default"; }
  fi
  if [ -n "$b" ]; then
    branch="${b#* }"
    [ "$current" = "$branch" ] || {
      echo "The open batch is $branch but the checkout is on '${current:-a detached HEAD}'; run sync first" >&2; exit 1; }
    git merge-base --is-ancestor "origin/$branch" HEAD || { echo "$branch is behind origin; preserve edits and run sync first" >&2; exit 1; }
  elif [[ "$current" == progress/* ]]; then
    branch="$current" # resume a committed batch after push/create failed
    [ "$branch" = progress/batch ] || {
      echo "Legacy orphan $branch: preserve its work, rename the local branch to progress/batch, inspect obsolete remote refs, then retry push" >&2; exit 1; }
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git merge-base --is-ancestor "origin/$branch" HEAD || { echo "Batch diverged; merge origin/$branch before retrying" >&2; exit 1; }
    fi
  else
    [ "$current" = "$default" ] || {
      echo "No batch is open; edit on $default after sync, not on '${current:-a detached HEAD}'" >&2; exit 1; }
    [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$default")" ] || {
      echo "Local $default differs from origin; run sync first" >&2; exit 1; }
    no_orphans
    branch=progress/batch
    git switch -q -c "$branch"
  fi
  fresh_batch HEAD
  git add -- "${paths[@]}"
  tracker_diff --cached
  if ! git diff --cached --quiet; then git commit -q -m "$subject"; fi
  git diff --quiet "origin/$default" HEAD && { echo "No tracker changes to publish" >&2; exit 1; }
  # Hooks can change the commit or HEAD. Validate and publish the same immutable tip.
  publish_oid="$(git rev-parse HEAD)"
  fresh_batch "$publish_oid" || {
    echo "Refusing push; commit $publish_oid remains unpublished. Preserve tracker evidence, rebuild tracker-only commits from origin/$default, and rerun reconcile" >&2; exit 1; }
  bash "$here/line-width.sh" check "origin/$default" "$publish_oid" >/dev/null || {
    echo "Refusing push; commit $publish_oid remains unpublished." \
      "Rewrap the reported tracker lines and rerun reconcile" >&2; exit 1; }
  git push -q origin "$publish_oid:refs/heads/$branch" || {
    echo "Batch push failed; local commit $publish_oid is preserved. Retry push after an outage; if another clone won, preserve this checkout, sync a clean clone, and rerun reconcile" >&2; exit 1; }
  git branch --set-upstream-to="origin/$branch" "$branch" >/dev/null
  publication_failed() {
    echo "Batch publication could not be verified: $*" >&2
    echo "Preserve this checkout and commit $publish_oid (pushed to origin/$branch)." >&2
    echo "Inspect open progress PRs; if none, open a PR on the preserved branch before sync:" >&2
    printf '  gh pr create --repo %q --base %q --head %q\n' "$repo" "$default" "$branch" >&2
    echo "Then run sync and retry push; sync imports the default after a web squash merge." >&2
    echo "If sync aborts a conflict, merge origin/$default on this branch, resolve retaining" >&2
    echo "both sets of tracker evidence, commit the resolution, then push before retrying sync." >&2
    echo "If the open head advanced, sync then push; if it diverged or uses another branch," >&2
    echo "preserve this clone, sync a clean clone, merge $publish_oid from this clone into" >&2
    echo "the open batch, resolve tracker conflicts retaining all evidence, then retry push." >&2
    exit 1
  }
  if [ -z "$b" ]; then
    gh pr create --repo "$repo" --base "$default" --head "$branch" \
      --title "docs(progress): batch tracker reconciliation" \
      --body "Tracker reconciliations batched for review; squash-merged at the next milestone." >/dev/null || {
      echo "Batch PR creation failed; $publish_oid is preserved locally and on origin/$branch. Retry push; if another clone opened the PR, sync a clean clone and rerun reconcile" >&2; exit 1; }
  fi
  readback="$(batch)" || publication_failed "cannot read open batches"
  [ -n "$readback" ] && [ "${readback#* }" = "$branch" ] || \
    publication_failed "no open batch reads back for $branch"
  [ -z "$b" ] || [ "$readback" = "$b" ] || \
    publication_failed "expected batch $b; found $readback"
  b="$readback"
  # GitHub can report the previous head for a few seconds after a push; re-read before failing.
  tries=0
  while :; do
    published="$(gh pr view "${b%% *}" --repo "$repo" \
      --json number,state,headRefName,headRefOid)" || publication_failed "cannot read batch head"
    jq -e --argjson pr "${b%% *}" --arg branch "$branch" '
      .number == $pr and .state == "OPEN" and .headRefName == $branch
    ' <<<"$published" >/dev/null || publication_failed "batch #${b%% *} is closed or changed"
    jq -e --arg oid "$publish_oid" '.headRefOid == $oid' <<<"$published" >/dev/null && break
    remote_head="$(git ls-remote origin "refs/heads/$branch")" || \
      publication_failed "cannot read remote batch head"
    [ "$remote_head" = "$(printf '%s\trefs/heads/%s' "$publish_oid" "$branch")" ] || \
      publication_failed "batch #${b%% *} remote head changed"
    tries=$((tries + 1))
    [ "$tries" -lt 5 ] || \
      publication_failed "batch #${b%% *} head did not read back after 5 attempts"
    sleep "${PROGRESS_PR_RETRY_DELAY:-2}"
  done
  echo "branch=$branch"
  echo "pr=${b%% *}"
  echo "commit=$publish_oid"
  exit 0
fi

subject="$1"
check_subject "$subject"; clean; guard
b="$(batch)"
if [ -z "$b" ]; then
  git fetch -q --prune origin; no_orphans
  checkout "$default"
  echo "no open progress batch; $default at $(git rev-parse --short HEAD)"
  exit 0
fi
pr="${b%% *}"; branch="${b#* }"
field() { gh pr view "$pr" --repo "$repo" --json "$1" --jq ".$1"; }
# Re-read the entire snapshot while the provider computes mergeability. The last
# snapshot supplies both the review gates and the exact head passed to the merge.
retry_delay="${PROGRESS_PR_RETRY_DELAY:-2}"
[[ "$retry_delay" =~ ^[0-5]$ ]] || { echo "PROGRESS_PR_RETRY_DELAY must be 0..5 seconds" >&2; exit 1; }
await_review() { echo "PRD batch awaiting review: $*" >&2; exit 2; }
for attempt in 1 2 3 4 5; do
  review="$(gh pr view "$pr" --repo "$repo" \
    --json isDraft,reviewDecision,latestReviews,statusCheckRollup,mergeStateStatus,headRefOid)" || {
    echo "Cannot read batch review state; retry provider lookup" >&2; exit 1; }
  jq -e '
    def text: type == "string" and length > 0;
    def valid_check:
      if .__typename == "CheckRun" then
        (.name | text) and
        (.status | IN("COMPLETED","IN_PROGRESS","PENDING","QUEUED","REQUESTED","WAITING")) and
        (.conclusion | IN(null,"","SUCCESS","SKIPPED","NEUTRAL","ACTION_REQUIRED",
          "CANCELLED","FAILURE","STALE","STARTUP_FAILURE","TIMED_OUT"))
      elif .__typename == "StatusContext" then
        (.context | text) and (.state | IN("SUCCESS","ERROR","FAILURE","PENDING","EXPECTED"))
      else false end;
    (.isDraft | type) == "boolean" and
    (.reviewDecision == "" or .reviewDecision == "APPROVED" or .reviewDecision == "REVIEW_REQUIRED" or .reviewDecision == "CHANGES_REQUESTED") and
    (.latestReviews | type) == "array" and all(.latestReviews[];
      (.author.login | text) and (.state | IN("APPROVED","CHANGES_REQUESTED","COMMENTED","DISMISSED","PENDING"))) and
    (.statusCheckRollup | type) == "array" and all(.statusCheckRollup[]; valid_check) and
    (.mergeStateStatus | type) == "string" and (.headRefOid | test("^[0-9a-f]{40}$"))' <<<"$review" >/dev/null || {
    echo "Invalid batch review state; retry provider lookup" >&2; exit 1; }
  merge_state="$(jq -r .mergeStateStatus <<<"$review")"
  if [ "$merge_state" = BLOCKED ]; then
    check_blockers="$(jq -r '[.statusCheckRollup[] |
      if .__typename == "CheckRun" then
        select(.status != "COMPLETED" or (.conclusion | IN("SUCCESS","SKIPPED","NEUTRAL") | not)) |
        "\(.name) (\(.status)/\(.conclusion // "pending"))"
      else select(.state != "SUCCESS") | "\(.context) (\(.state))" end] | join(", ")' <<<"$review")"
    [ -z "$check_blockers" ] || {
      echo "Batch #$pr check blocker: $check_blockers; inspect PR checks, wait or repair, then retry" >&2
      exit 1
    }
  fi
  [ "$(jq -r .isDraft <<<"$review")" = false ] || await_review "Batch #$pr is a draft"
  # latestReviews contains each author's latest submitted state, even without review rules.
  if jq -e '.reviewDecision == "CHANGES_REQUESTED" or
    any(.latestReviews[]; .state == "CHANGES_REQUESTED")' <<<"$review" >/dev/null; then
    await_review "Batch #$pr has requested changes"
  fi
  # A review the running account started but never submitted is still in progress.
  if jq -e 'any(.latestReviews[]; .state == "PENDING")' <<<"$review" >/dev/null; then
    await_review "Batch #$pr has a review in progress"
  fi
  [ "$merge_state" = UNKNOWN ] || break
  [ "$attempt" -lt 5 ] || {
    echo "Batch #$pr provider merge state is UNKNOWN after 5 snapshots; retry when computation completes" >&2; exit 1; }
  sleep "$retry_delay"
done
# gh returns one provider page of reviews and checks; their totals must fit what was evaluated.
counts="$(gh api graphql -F owner="${repo%%/*}" -F name="${repo#*/}" -F number="$pr" \
  -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){headRefOid latestReviews(first:1){totalCount} latestOpinionatedReviews(first:100){totalCount nodes{state author{login}}} commits(last:1){nodes{commit{statusCheckRollup{contexts(first:1){totalCount}}}}}}}}')" || {
  echo "Cannot count batch reviews and checks; retry provider lookup" >&2; exit 1; }
jq -e --argjson snap "$review" '.data.repository.pullRequest as $p |
  $p.headRefOid == $snap.headRefOid and ($p.latestReviews.totalCount | type) == "number" and
  $p.latestReviews.totalCount <= ($snap.latestReviews | length) and
  ($p.latestOpinionatedReviews.nodes | type) == "array" and
  $p.latestOpinionatedReviews.totalCount <= ($p.latestOpinionatedReviews.nodes | length) and
  all($p.latestOpinionatedReviews.nodes[]; (.author == null or (.author.login | type) == "string")
    and (.state | IN("APPROVED","CHANGES_REQUESTED","COMMENTED","DISMISSED"))) and
  ($p.commits.nodes[0].commit.statusCheckRollup.contexts.totalCount // 0) <= ($snap.statusCheckRollup | length)
' <<<"$counts" >/dev/null || {
  echo "Batch #$pr has more reviews or checks than one provider page, invalid review data, or its head moved; inspect the PR, then retry" >&2
  exit 1
}
# latestReviews keeps each reviewer's newest review, so a later comment can hide an outstanding
# change request; opinionated reviews keep it until the reviewer approves or it is dismissed.
if jq -e 'any(.data.repository.pullRequest.latestOpinionatedReviews.nodes[];
  .state == "CHANGES_REQUESTED")' <<<"$counts" >/dev/null; then
  await_review "Batch #$pr has requested changes"
fi
threads="$(gh api graphql --paginate --slurp -F owner="${repo%%/*}" -F name="${repo#*/}" -F number="$pr" \
  -f query='query($owner:String!,$name:String!,$number:Int!,$endCursor:String){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100,after:$endCursor){nodes{isResolved} pageInfo{hasNextPage endCursor}}}}}')" || {
  echo "Cannot read all review threads; retry provider lookup" >&2; exit 1; }
unresolved="$(jq -er '
  if type != "array" or length == 0 then error("missing pages") else . end |
  if any(.[]; .errors != null or (.data.repository.pullRequest.reviewThreads.nodes | type) != "array"
    or (.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage | type) != "boolean")
    or .[-1].data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage != false then error("incomplete threads") else . end |
  [.[].data.repository.pullRequest.reviewThreads.nodes[] |
    if (.isResolved | type) != "boolean" then error("invalid thread") else . end |
    select(.isResolved | not)] | length' <<<"$threads")" || {
  echo "Invalid review threads response; retry provider lookup" >&2; exit 1; }
[ "$unresolved" = 0 ] || await_review "Batch #$pr has $unresolved unresolved review thread(s)"
merge_state="$(jq -r .mergeStateStatus <<<"$review")"
case "$merge_state" in
  CLEAN) ;;
  BLOCKED)
    [ "$(jq -r .reviewDecision <<<"$review")" != REVIEW_REQUIRED ] || \
      await_review "Batch #$pr requires review"
    echo "Batch #$pr is BLOCKED without a review cause; inspect branch rules and PR checks, then retry" >&2
    exit 1;;
  DRAFT) await_review "Batch #$pr merge state is $merge_state, not CLEAN";;
  DIRTY) echo "Batch #$pr has a merge conflict; resolve it before retrying" >&2; exit 1;;
  BEHIND) echo "Batch #$pr is BEHIND: the provider requires a base update; run sync, push, then retry merge" >&2; exit 1;;
  *) echo "Batch #$pr provider merge state is $merge_state; retry once it resolves to CLEAN" >&2; exit 1;;
esac
head_oid="$(jq -r .headRefOid <<<"$review")"
git fetch -q --prune origin
tracker_batch "$head_oid"
local_oid=""
if git show-ref --verify --quiet "refs/heads/$branch"; then
  local_oid="$(git rev-parse "refs/heads/$branch")"
  only_base_merges "$local_oid" "$head_oid" || {
    echo "Local $branch has unpublished tracker work or unverified merges; publish it before merging batch #$pr" >&2; exit 1; }
fi
body="$(git log --no-merges --reverse --format='- %s' "origin/$default..$head_oid")"
landed="$subject (#$pr)"
# Bind the merge to the reviewed head: a push in between fails the merge instead of landing unseen.
gh pr merge "$pr" --repo "$repo" --squash --match-head-commit "$head_oid" --subject "$landed" --body "$body"
[ "$(field state)" = MERGED ] || { echo "Batch #$pr is not MERGED after the merge" >&2; exit 1; }
oid="$(gh pr view "$pr" --repo "$repo" --json mergeCommit --jq '.mergeCommit.oid // ""')"
[ -n "$oid" ] || { echo "Batch #$pr is MERGED but GitHub reports no merge commit" >&2; exit 1; }
[ "$(gh api "repos/$repo/commits/$oid" --jq '.parents | length')" = 1 ] || { echo "Merged $oid is not a squash" >&2; exit 1; }
[ "$(gh api "repos/$repo/commits/$oid" --jq '.commit.message' | sed -n 1p)" = "$landed" ] || {
  echo "Merged $oid does not carry the subject '$landed'" >&2; exit 1; }
# The shared checkout neutralizes branch merge options and verifies the reached commit.
checkout "$default"
git merge-base --is-ancestor "$oid" HEAD || {
  echo "Local $default does not contain the merged $oid; batch #$pr is merged, so run sync to refresh" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=all)" ] || {
  echo "Refresh after merging batch #$pr left a dirty tree; preserve it, then run sync" >&2; exit 1; }
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
