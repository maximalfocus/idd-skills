#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${PROGRESS_PR_SCRIPT:-$root/scripts/progress-pr.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$tmp/bin"
export PROGRESS_PR_RETRY_DELAY=0
export PROGRESS_TEST_ROOT="$tmp" PATH="$tmp/bin:$PATH"

# The fake gh keeps one PR in state files: open-pr holds "<number> <branch>" while
# it is open, and a merge performs a real squash of the head onto origin/main.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${PROGRESS_TEST_ROOT:?}"
advance_head() {
  local head tip moved
  head="$(cat "$root/pr-head")"; tip="$(git rev-parse "origin/$head")"
  moved="$(git commit-tree "$tip^{tree}" -p "$tip" -m 'docs(progress): remote snapshot update')"
  git push -q origin "$moved:refs/heads/$head"
  echo "$moved" > "$root/snapshot-expected-head"
}
if [ "$1 $2" = "repo view" ]; then
  [[ "$*" == *nameWithOwner* ]] && echo example/demo-prd || echo main
elif [ "$1 $2" = "pr list" ]; then
  [ ! -f "$root/fail-list" ] || { echo "simulated list outage" >&2; exit 1; }
  [ ! -f "$root/late-batch" ] || exit 0
  cat "$root/open-pr"
elif [ "$1 $2" = "pr create" ]; then
  [ ! -f "$root/fail-create" ] || { echo "simulated create outage" >&2; exit 1; }
  while [ "$#" -gt 0 ]; do case "$1" in --head) head="$2"; shift;; esac; shift; done
  # Model GitHub's atomic uniqueness constraint for one open PR per head/base pair.
  mkdir "$root/create-lock" 2>/dev/null || { echo "PR creation already in progress" >&2; exit 1; }
  trap 'rmdir "$root/create-lock"' EXIT
  ! grep -Fxq "7 $head" "$root/open-pr" || { echo "an open PR already exists" >&2; exit 1; }
  echo "7 $head" >> "$root/open-pr"; echo "$head" > "$root/pr-head"; echo OPEN > "$root/pr-state"
  printf 'x' >> "$root/create-count"; echo "https://github.com/example/demo-prd/pull/7"
elif [ "$1 $2" = "pr view" ]; then
  [ ! -f "$root/fail-review" ] || { echo "simulated review outage" >&2; exit 1; }
  case "${*: -1}" in
    number,state,headRefName,headRefOid)
      printf x >> "$root/head-read-count"
      head="$(cat "$root/pr-head")"
      state="$(cat "$root/pr-state" 2>/dev/null || echo OPEN)"
      oid="$(git ls-remote origin "refs/heads/$head" | cut -f1)"
      # stale-reads models GitHub reporting the previous head for a few reads after a push.
      if [ -s "$root/stale-reads" ]; then
        oid="$(cat "$root/stale-head")"
        # Rewrite without the incompatible BSD/GNU `sed -i` option forms.
        sed '$d' "$root/stale-reads" > "$root/stale-reads.n"
        mv "$root/stale-reads.n" "$root/stale-reads"
      fi
      jq -n --argjson number "$3" --arg state "$state" --arg head "$head" \
        --arg oid "$oid" \
        '{number:$number,state:$state,headRefName:$head,headRefOid:$oid}' ;;
    isDraft,reviewDecision,*)
      count="$(cat "$root/snapshot-count" 2>/dev/null || echo 0)"; count=$((count + 1))
      echo "$count" > "$root/snapshot-count"
      if [ -f "$root/snapshot-sequence" ]; then
        state="$(sed -n "${count}p" "$root/snapshot-sequence")"
        [ -z "$state" ] || echo "$state" > "$root/merge-state"
      fi
      git fetch -q origin
      if [ "$count" = 3 ] && [ -f "$root/snapshot-effect" ]; then
        case "$(cat "$root/snapshot-effect")" in
          draft) echo true > "$root/draft";;
          requested) echo CHANGES_REQUESTED > "$root/review";;
          latest)
            echo '[{"author":{"login":"maintainer"},"state":"CHANGES_REQUESTED"}]' \
              > "$root/latest-reviews";;
          checks)
            echo BLOCKED > "$root/merge-state"
            echo '[{"__typename":"StatusContext","context":"ci","state":"PENDING"}]' \
              > "$root/checks";;
          threads) echo 1 > "$root/unresolved";;
          head) advance_head;;
        esac
      fi
      jq -n --argjson draft "$(cat "$root/draft")" --arg review "$(cat "$root/review")" \
        --argjson latest "$(cat "$root/latest-reviews")" --argjson checks "$(cat "$root/checks")" \
        --arg state "$(cat "$root/merge-state")" --arg oid "$(git rev-parse "origin/$(cat "$root/pr-head")")" \
        '{isDraft:$draft,reviewDecision:$review,mergeStateStatus:$state,headRefOid:$oid,
          latestReviews:$latest,statusCheckRollup:$checks}' ;;
    .isDraft) cat "$root/draft";;
    .reviewDecision) cat "$root/review";;
    .mergeStateStatus) cat "$root/merge-state";;
    .headRefOid) git fetch -q origin; git rev-parse "origin/$(cat "$root/pr-head")";;
    .state) cat "$root/pr-state";;
    '.mergeCommit.oid // ""') cat "$root/merge-oid";;
    *) echo "unexpected pr view key: ${*: -1}" >&2; exit 2;;
  esac
elif [ "$1 $2" = "pr merge" ]; then
  while [ "$#" -gt 0 ]; do
    case "$1" in --subject) subject="$2"; shift;; --body) body="$2"; shift;; --match-head-commit) match="$2"; shift;; esac
    shift
  done
  head="$(cat "$root/pr-head")"; git fetch -q origin
  [ "$match" = "$(git rev-parse "origin/$head")" ] || { echo "Head branch was modified" >&2; exit 1; }
  merged_tree="$(git merge-tree --write-tree origin/main "origin/$head")"
  echo "$match" > "$root/pr-merged-head"; echo "$head" > "$root/pr-merged-branch"
  oid="$(git commit-tree "$merged_tree" -p "$(git rev-parse origin/main)" -m "$subject" -m "$body")"
  git push -q --no-verify origin "$oid:main"
  echo "$oid" > "$root/merge-oid"; echo MERGED > "$root/pr-state"; : > "$root/open-pr"; printf 'x' >> "$root/merge-count"
elif [ "$1 $2" = "api graphql" ] && [[ "$*" == *totalCount* ]]; then
  [ ! -f "$root/advance-before-counts" ] || advance_head
  git fetch -q origin
  jq -n --arg oid "$(git rev-parse "origin/$(cat "$root/pr-head")")" \
    --argjson reviews "$(cat "$root/review-total" 2>/dev/null || jq length "$root/latest-reviews")" \
    --argjson checks "$(cat "$root/check-total" 2>/dev/null || jq length "$root/checks")" \
    --argjson opinionated "$(cat "$root/opinionated-reviews" 2>/dev/null || echo '[]')" \
    --argjson opTotal "$(cat "$root/opinionated-total" 2>/dev/null || echo null)" \
    '{data:{repository:{pullRequest:{headRefOid:$oid,latestReviews:{totalCount:$reviews},
      latestOpinionatedReviews:{totalCount:($opTotal // ($opinionated | length)),nodes:$opinionated},
      commits:{nodes:[{commit:{statusCheckRollup:{contexts:{totalCount:$checks}}}}]}}}}}'
elif [ "$1 $2" = "api graphql" ]; then
  [ ! -f "$root/advance-after-snapshot" ] || advance_head
  [ ! -f "$root/fail-threads" ] || { echo "simulated threads outage" >&2; exit 1; }
  if [[ "$*" == *--paginate* && "$*" == *'after:$endCursor'* && "$*" == *pageInfo* ]]; then
    jq -n --argjson count "$(cat "$root/unresolved")" --argjson late "$(cat "$root/late-thread")" '
      def page($nodes;$next): {data:{repository:{pullRequest:{reviewThreads:{nodes:$nodes,pageInfo:{hasNextPage:$next,endCursor:"cursor"}}}}}};
      [page([range(0;$count)|{isResolved:false}];$late)] +
      (if $late then [page([{isResolved:false}];false)] else [] end)'
  else cat "$root/unresolved"; fi
elif [ "$1" = api ] && [[ "$*" == *"repos/example/demo-prd/pulls"* ]]; then
  [ ! -f "$root/fail-list" ] || { echo "simulated list outage" >&2; exit 1; }
  [[ "$*" == *--paginate* && "$*" == *--slurp* ]] || { echo "PR lookup must paginate" >&2; exit 1; }
  if [[ "$*" == *state=closed* ]]; then
    if [ -f "$root/pr-merged-head" ]; then
      jq -n --arg head "$(cat "$root/pr-merged-branch")" --arg oid "$(cat "$root/pr-merged-head")" \
        '[[{merged_at:"merged",base:{ref:"main"},head:{ref:$head,sha:$oid,repo:{full_name:"example/demo-prd"}}}]]'
    else echo '[[]]'; fi
    exit 0
  fi
  jq -Rn '[inputs | split(" ") | {number:(.[0]|tonumber),head:{ref:.[1],repo:{full_name:"example/demo-prd"}}}] | [[],.]' < "$root/open-pr"
  # Close/merge after returning the lookup snapshot but before the caller pushes.
  race="$(cat "$root/publish-race" 2>/dev/null || true)"
  case "$race" in
    closed) rm "$root/publish-race"; : > "$root/open-pr"; echo CLOSED > "$root/pr-state";;
    merged)
      rm "$root/publish-race"
      before="$(git rev-parse origin/main)"
      gh pr merge 7 --subject 'docs(progress): web milestone (#7)' --body 'web merge' \
        --match-head-commit "$(git rev-parse "origin/$(cat "$root/pr-head")")" >/dev/null
      # A web merge does not update the caller's remote-tracking ref until its next fetch.
      git update-ref refs/remotes/origin/main "$before";;
  esac
elif [ "$1" = api ]; then
  oid="${2##*/}"; git fetch -q origin
  case "${*: -1}" in
    '.parents | length') git rev-list --parents -n1 "$oid" | wc -w | awk '{print $1-1}';;
    .commit.message) git log -1 --format=%B "$oid";;
  esac
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"

fresh() {
  rm -rf "$tmp/origin.git" "$tmp/demo-prd" "$tmp"/open-pr "$tmp"/pr-* "$tmp"/merge-* "$tmp"/create-count "$tmp"/fail-* "$tmp"/late-* "$tmp"/snapshot-* "$tmp"/advance-after-snapshot "$tmp"/advance-before-counts "$tmp"/review-total "$tmp"/check-total "$tmp"/opinionated-reviews "$tmp"/opinionated-total
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/demo-prd" 2>/dev/null
  ( cd "$tmp/demo-prd"; git switch -q -c main 2>/dev/null || true
    printf 'prd\n' > PRD.md; printf 'progress\n' > PROGRESS.md; git add .; git commit -qm "docs: init"
    git push -q -u origin main )
  : > "$tmp/open-pr"; echo "" > "$tmp/review"; echo CLEAN > "$tmp/merge-state"; echo 0 > "$tmp/unresolved"; echo false > "$tmp/draft"; echo false > "$tmp/late-thread"
  echo '[]' > "$tmp/latest-reviews"; echo '[]' > "$tmp/checks"
}
run() { bash "$script" "$@"; }
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err before; shift 2
  before="$(cat "$tmp/merge-count" 2>/dev/null || true)"
  if err="$("$@" 2>&1 >/dev/null)"; then echo "progress-pr accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "progress-pr rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
  [ "$(cat "$tmp/merge-count" 2>/dev/null || true)" = "$before" ] || { echo "a refusal must not merge ($desc)" >&2; exit 1; }
}
warns() {
  local desc="$1" want="$2" err; shift 2
  err="$("$@" 2>&1 >/dev/null)" || { echo "must continue with $desc: $err" >&2; exit 1; }
  [[ "$err" == *"guard NOT installed"* && "$err" == *"$want"* ]] || {
    echo "missing guard warning for $desc: $err" >&2; exit 1; }
}
prd="$tmp/demo-prd"
on() { git -C "$prd" symbolic-ref --short HEAD; }

# --- unprotected batches honor each reviewer's latest submitted review ------------
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): reviewed row" PROGRESS.md >/dev/null
echo '[{"author":{"login":"maintainer"},"state":"CHANGES_REQUESTED"}]' \
  > "$tmp/latest-reviews"
code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
[ "$code" = 2 ] && [[ "$err" == *"PRD batch awaiting review"* ]] || {
  echo "unprotected requested changes must refuse with exit 2: $code $err" >&2; exit 1; }
[ ! -f "$tmp/merge-count" ]
# The running account's own unsubmitted review is a review in progress, not invalid data.
echo '[{"author":{"login":"maintainer"},"state":"PENDING"}]' > "$tmp/latest-reviews"
code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
[ "$code" = 2 ] && [[ "$err" == *"review in progress"* ]] || {
  echo "a pending review must refuse with exit 2: $code $err" >&2; exit 1; }
[ ! -f "$tmp/merge-count" ]
# The provider's latestReviews replaces the same author's earlier request.
echo '[{"author":{"login":"maintainer"},"state":"APPROVED"}]' > "$tmp/latest-reviews"
run merge "$prd" "docs(progress): approved milestone" >/dev/null
[ "$(cat "$tmp/merge-count")" = x ]

# --- BLOCKED checks are plumbing failures, including legacy commit statuses --------
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): checked row" PROGRESS.md >/dev/null
echo BLOCKED > "$tmp/merge-state"
for check in \
  '{"__typename":"CheckRun","name":"ci","status":"IN_PROGRESS","conclusion":""}' \
  '{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"FAILURE"}' \
  '{"__typename":"StatusContext","context":"ci","state":"PENDING"}' \
  '{"__typename":"StatusContext","context":"ci","state":"ERROR"}'; do
  echo "[$check]" > "$tmp/checks"
  code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
  [ "$code" = 1 ] && [[ "$err" == *"check blocker: ci"* && "$err" != *"awaiting review"* ]] || {
    echo "BLOCKED checks must refuse with exit 1: $code $err" >&2; exit 1; }
  [ ! -f "$tmp/merge-count" ]
done
echo '[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"},
  {"__typename":"StatusContext","context":"legacy","state":"SUCCESS"}]' > "$tmp/checks"
echo REVIEW_REQUIRED > "$tmp/review"
code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
[ "$code" = 2 ]; [[ "$err" == *"PRD batch awaiting review"* ]]
[ ! -f "$tmp/merge-count" ]

# --- malformed review/check evidence fails closed before a merge ------------------
echo CLEAN > "$tmp/merge-state"; echo '' > "$tmp/review"; echo '[]' > "$tmp/checks"
for field in latest-reviews checks; do
  for invalid in null '{}' '[{}]' '[{"state":"UNRECOGNIZED","author":{"login":"m"}}]'; do
    echo "$invalid" > "$tmp/$field"
    code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
    [ "$code" = 1 ]; [[ "$err" == *"Invalid batch review state"* ]]
    [ ! -f "$tmp/merge-count" ]
  done
  echo '[]' > "$tmp/$field"
done

# --- sync fast-forwards HEAD despite branch mergeOptions=--squash ------------------
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): first row" PROGRESS.md >/dev/null
before="$(git -C "$prd" rev-parse HEAD)"
printf 'remote row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): remote row" PROGRESS.md >/dev/null
expected="$(git -C "$prd" rev-parse HEAD)"
git -C "$prd" reset -q --hard "$before"
git -C "$prd" config branch.progress/batch.mergeOptions --squash
out="$(run sync "$prd")"
[ "$(git -C "$prd" rev-parse HEAD)" = "$expected" ] || {
  echo 'sync reported success without advancing HEAD to the remote batch' >&2; exit 1; }
[ -z "$(git -C "$prd" status --porcelain --untracked-files=all)" ]
grep -qx 'branch=progress/batch' <<<"$out"
grep -qx 'remote row' "$prd/PROGRESS.md"
[ "$(git -C "$prd" config branch.progress/batch.mergeOptions)" = --squash ]

# A successful Git exit alone cannot satisfy checkout or the final clean-tree gate.
git -C "$prd" reset -q --hard "$before"
export PROGRESS_TEST_REAL_GIT="$(command -v git)"
cat > "$tmp/bin/git" <<'GIT'
#!/bin/bash
[[ "$*" != *'--ff-only'* ]] || exit 0
exec "$PROGRESS_TEST_REAL_GIT" "$@"
GIT
chmod +x "$tmp/bin/git"
refuses "a no-op checkout merge" "Checkout did not reach $expected" run sync "$prd"
rm "$tmp/bin/git"
printf '#!/bin/sh\necho generated > sync-generated.txt\n' > "$prd/.git/hooks/post-merge"
chmod +x "$prd/.git/hooks/post-merge"
refuses "generated sync dirt" "Sync left a dirty tree; preserve generated changes" run sync "$prd"
[ "$(git -C "$prd" rev-parse HEAD)" = "$expected" ]
grep -qx generated "$prd/sync-generated.txt"

# --- the post-merge refresh reaches the landed default despite mergeOptions=--squash --
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): squash-proof row" PROGRESS.md >/dev/null
git -C "$prd" config branch.main.mergeOptions --squash
run merge "$prd" "docs(progress): squash-proof milestone" >/dev/null
[ "$(on)" = main ] || { echo "merge must return to main" >&2; exit 1; }
[ "$(git -C "$prd" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || {
  echo 'merge refresh left main behind the landed squash' >&2; exit 1; }
[ -z "$(git -C "$prd" status --porcelain --untracked-files=all)" ] || {
  echo 'merge refresh left a dirty tree' >&2; exit 1; }
[ "$(git -C "$prd" config branch.main.mergeOptions)" = --squash ]

# --- sync with no batch stays on main and guards it ------------------------------
fresh
out="$(run sync "$prd")"
[ "$out" = "$(printf 'branch=main\npr=')" ] || { echo "unexpected sync output: $out" >&2; exit 1; }
printf 'direct\n' >> "$prd/PROGRESS.md"; git -C "$prd" commit -qam "docs(progress): direct"
if err="$(git -C "$prd" push -q origin main 2>&1)"; then echo "the guard must refuse a direct push to main" >&2; exit 1; fi
case "$err" in *"changes only through a pull request"*) ;; *) echo "wrong guard refusal: $err" >&2; exit 1;; esac
git -C "$prd" reset -q --hard origin/main

# --- the first push opens the batch; main is untouched ---------------------------
printf 'row 1\n' >> "$prd/PROGRESS.md"
out="$(run push "$prd" "docs(progress): reconcile example/demo#1" PROGRESS.md)"
branch="$(sed -n 's/^branch=//p' <<<"$out")"
[ "$branch" = progress/batch ] || { echo "unexpected batch branch: $branch" >&2; exit 1; }
grep -qx 'pr=7' <<<"$out" || { echo "push must report the opened batch: $out" >&2; exit 1; }
[ "$(on)" = "$branch" ] || { echo "push must leave the checkout on the batch" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 1 ] || { echo "push must not change main" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = "$(git -C "$prd" rev-parse HEAD)" ] || { echo "the batch must be pushed" >&2; exit 1; }

# --- refusals before any commit ----------------------------------------------------
printf 'stray\n' >> "$prd/PRD.md"; printf 'row x\n' >> "$prd/PROGRESS.md"
refuses "a change outside the named paths" "outside the named paths" \
  run push "$prd" "docs(progress): reconcile example/demo#2" PROGRESS.md
git -C "$prd" checkout -q -- .
printf 'row x\n' >> "$prd/PROGRESS.md"
refuses "an untyped subject" "docs(progress): <lowercase summary>" \
  run push "$prd" "reconcile example/demo#2" PROGRESS.md
refuses "a sync over a dirty tree" "dirty PRD tree" run sync "$prd"
git -C "$prd" checkout -q -- .

# --- a tracker row honors the shared line width before it is published -----------
printf '%0101d\n' 0 >> "$prd/PROGRESS.md"
refuses "a tracker row over 100 characters" "Rewrap the reported tracker lines" \
  run push "$prd" "docs(progress): wide row" PROGRESS.md
git -C "$tmp/origin.git" rev-parse "$branch" >/dev/null
[ "$(git -C "$tmp/origin.git" rev-list --count "$branch")" = 2 ] || {
  echo "a wide row must not be pushed" >&2; exit 1; }
git -C "$prd" reset -q --hard "origin/$branch"

# --- a second push joins the same batch, even after a sync from main ---------------
git -C "$prd" switch -q main
out="$(run sync "$prd")"
[ "$out" = "$(printf 'branch=%s\npr=7' "$branch")" ] || { echo "sync must check out the open batch: $out" >&2; exit 1; }
printf 'row 2\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): reconcile example/demo#2" PROGRESS.md >/dev/null
[ "$(cat "$tmp/create-count")" = x ] || { echo "a second push must not open a second batch" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count "$branch")" = 3 ] || { echo "the batch must carry both reconciles" >&2; exit 1; }

# --- merge refuses review state it must not bypass ---------------------------------
echo 1 > "$tmp/unresolved"
refuses "an unresolved review thread" "unresolved review thread" \
  run merge "$prd" "docs(progress): validate slice one"
echo 0 > "$tmp/unresolved"; echo CHANGES_REQUESTED > "$tmp/review"
refuses "requested changes" "requested changes" \
  run merge "$prd" "docs(progress): validate slice one"
echo "" > "$tmp/review"; echo DIRTY > "$tmp/merge-state"
refuses "a conflicting batch" "merge conflict" run merge "$prd" "docs(progress): validate slice one"
echo CLEAN > "$tmp/merge-state"
refuses "an untyped merge subject" "docs(progress): <lowercase summary>" \
  run merge "$prd" "Validate slice one"
echo "8 progress/other" >> "$tmp/open-pr"
refuses "two open batches" "move the commits onto one batch, close the others, then retry" \
  run merge "$prd" "docs(progress): validate slice one"
echo "7 $branch" > "$tmp/open-pr"

# --- the milestone merge lands one squash commit and removes the batch -------------
out="$(run merge "$prd" "docs(progress): validate slice one")"
grep -qx 'subject=docs(progress): validate slice one (#7)' <<<"$out" || {
  echo "unexpected merge output: $out" >&2; exit 1; }
[ "$(on)" = main ] || { echo "merge must return to main" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 2 ] || { echo "the batch must land as exactly one commit" >&2; exit 1; }
[ "$(git -C "$prd" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "local main must equal origin" >&2; exit 1; }
want="$(printf '%s\n\n%s\n%s' 'docs(progress): validate slice one (#7)' \
  '- docs(progress): reconcile example/demo#1' '- docs(progress): reconcile example/demo#2')"
[ "$(git -C "$prd" log -1 --format=%B)" = "$want" ] || { echo "the landed body must list the batched reconciles" >&2; exit 1; }
[ "$(tail -2 "$prd/PROGRESS.md" | tr '\n' ' ')" = "row 1 row 2 " ] || { echo "merged tracker content must be checked out" >&2; exit 1; }
! git -C "$prd" show-ref --verify --quiet "refs/heads/$branch" || { echo "the local batch must be deleted" >&2; exit 1; }
! git -C "$tmp/origin.git" show-ref --verify --quiet "refs/heads/$branch" || { echo "the remote batch must be deleted" >&2; exit 1; }
out="$(run merge "$prd" "docs(progress): validate slice one")"
[ "$out" = "no open progress batch; main at $(git -C "$prd" rev-parse --short HEAD)" ] || { echo "a merge with no batch must be a no-op: $out" >&2; exit 1; }

# --- someone else's pre-push hook is never overwritten -----------------------------
fresh
printf '#!/bin/sh\nexit 0\n' > "$prd/.git/hooks/pre-push"
warns "a foreign hook" "existing pre-push hook left untouched" run sync "$prd"
[ "$(cat "$prd/.git/hooks/pre-push")" = "$(printf '#!/bin/sh\nexit 0')" ] || { echo "a foreign hook must be left unchanged" >&2; exit 1; }

# --- literal paths and committed contamination cannot enter a batch ----------------
fresh
printf 'contract edit\n' >> "$prd/PRD.md"
refuses "an explicitly named contract" "literal tracker path" \
  run push "$prd" "docs(progress): invalid" PRD.md
refuses "a broad pathspec" "literal tracker path" run push "$prd" "docs(progress): invalid" .
git -C "$prd" checkout -q -- .
mkdir -p "$prd/contexts/core"
printf 'context progress\n' > "$prd/contexts/core/PROGRESS.md"
run push "$prd" "docs(progress): context row" contexts/core/PROGRESS.md >/dev/null
printf 'contract edit\n' >> "$prd/PRD.md"; git -C "$prd" commit -qam "docs: stray contract"
printf 'row\n' >> "$prd/PROGRESS.md"
refuses "committed non-tracker content" "Non-tracker path" \
  run push "$prd" "docs(progress): invalid" PROGRESS.md
git -C "$prd" checkout -q -- .
git -C "$prd" push -q origin HEAD
refuses "a contaminated merge" "Non-tracker path" run merge "$prd" "docs(progress): invalid"
git -C "$prd" checkout -q origin/main -- PRD.md
git -C "$prd" commit -qm "docs: revert stray contract"
printf 'row\n' >> "$prd/PROGRESS.md"
refuses "reverted non-tracker history" "Non-tracker path" \
  run push "$prd" "docs(progress): invalid" PROGRESS.md

# --- configured/shared, symlinked, and marker-containing hooks are untouched --------
fresh
mkdir -p "$tmp/shared-hooks"
git -C "$prd" config core.hooksPath "$tmp/shared-hooks"
warns "shared hooks" "core.hooksPath left untouched" run sync "$prd"
[ ! -e "$tmp/shared-hooks/pre-push" ]
git -C "$prd" config --unset core.hooksPath
printf '#!/bin/sh\n# idd-progress-guard custom\nexit 0\n' > "$tmp/foreign-hook"
ln -s "$tmp/foreign-hook" "$prd/.git/hooks/pre-push"
warns "a hook symlink" "symlinked hooks left untouched" run sync "$prd"
rm "$prd/.git/hooks/pre-push"
cp "$tmp/foreign-hook" "$prd/.git/hooks/pre-push"
warns "a foreign marker hook" "existing pre-push hook" run sync "$prd"
cmp "$tmp/foreign-hook" "$prd/.git/hooks/pre-push"
chmod +x "$prd/.git/hooks/pre-push"
printf 'row\n' >> "$prd/PROGRESS.md"
warns "push with a foreign hook" "existing pre-push hook" \
  run push "$prd" "docs(progress): hooked row" PROGRESS.md
warns "merge with a foreign hook" "existing pre-push hook" \
  run merge "$prd" "docs(progress): hooked milestone"
cmp "$tmp/foreign-hook" "$prd/.git/hooks/pre-push"

# --- a newer default must be incorporated before any batch reader/writer proceeds ---
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): initial row" PROGRESS.md >/dev/null
branch="$(on)"
( cd "$prd"; git switch -q --detach origin/main
  printf 'new requirement\n' >> PRD.md; git commit -qam 'docs: new requirement'
  git push -q --no-verify origin HEAD:main; git switch -q "$branch" )
remote_before="$(git -C "$tmp/origin.git" rev-parse "$branch")"
run sync "$prd" >/dev/null
grep -qx 'new requirement' "$prd/PRD.md"
[ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = "$remote_before" ]
local_merge="$(git -C "$prd" rev-parse HEAD)"
run sync "$prd" >/dev/null # local-only mechanical merges must remain resumable
[ "$(git -C "$prd" rev-parse HEAD)" = "$local_merge" ]
printf 'next row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): next row" PROGRESS.md >/dev/null
[ "$(git -C "$prd" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse "$branch")" ]
run merge "$prd" "docs(progress): milestone" >/dev/null
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 3 ]
grep -qx 'new requirement' "$prd/PRD.md"; grep -qx 'next row' "$prd/PROGRESS.md"
landed_message="$(printf '%s\n\n%s\n%s' 'docs(progress): milestone (#7)' \
  '- docs(progress): initial row' '- docs(progress): next row')"
[ "$(git -C "$prd" log -1 --format=%B)" = "$landed_message" ]

# An older reviewed head merges onto current default, dropping only safe local sync merges.
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): initial row" PROGRESS.md >/dev/null
branch="$(on)"
( cd "$prd"; git switch -q --detach origin/main
  printf 'new requirement\n' >> PRD.md; git commit -qam 'docs: new requirement'
  git push -q --no-verify origin HEAD:main; git switch -q "$branch" )
run sync "$prd" >/dev/null
run merge "$prd" "docs(progress): milestone" >/dev/null
grep -qx 'new requirement' "$prd/PRD.md"
! git -C "$prd" show-ref --verify --quiet "refs/heads/$branch"

# Another clone advances the batch while this clone holds only a local sync merge.
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): initial row" PROGRESS.md >/dev/null
branch="$(on)"
( cd "$prd"; git switch -q --detach origin/main
  printf 'new requirement\n' >> PRD.md; git commit -qam 'docs: new requirement'
  git push -q --no-verify origin HEAD:main; git switch -q "$branch" )
run sync "$prd" >/dev/null
( cd "$prd"; git switch -q --detach "origin/$branch"
  printf 'remote row\n' >> PROGRESS.md; git commit -qam 'docs(progress): remote row'
  git push -q origin "HEAD:$branch"; git switch -q "$branch" )
remote_before="$(git -C "$tmp/origin.git" rev-parse "$branch")"
run sync "$prd" >/dev/null
run sync "$prd" >/dev/null
grep -qx 'new requirement' "$prd/PRD.md"; grep -qx 'remote row' "$prd/PROGRESS.md"
[ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = "$remote_before" ]

# A conflict aborts the mechanical merge and preserves the clean batch tree and evidence.
fresh
printf 'batch edit\n' > "$prd/PROGRESS.md"
run push "$prd" "docs(progress): batch row" PROGRESS.md >/dev/null
branch="$(on)"; before="$(git -C "$prd" rev-parse HEAD)"
( cd "$prd"; git switch -q --detach origin/main
  printf 'default edit\n' > PROGRESS.md; git commit -qam 'docs: tracker correction'
  git push -q --no-verify origin HEAD:main; git switch -q "$branch" )
refuses "a sync conflict" "Cannot merge origin/main" run sync "$prd"
[ "$(git -C "$prd" rev-parse HEAD)" = "$before" ]
[ -z "$(git -C "$prd" status --porcelain)" ]
! git -C "$prd" rev-parse -q --verify MERGE_HEAD >/dev/null
grep -qx 'batch edit' "$prd/PROGRESS.md"

# A fabricated merge resolution is authored evidence, not a disposable sync merge.
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): initial row" PROGRESS.md >/dev/null
branch="$(on)"
( cd "$prd"; git switch -q --detach origin/main
  printf 'new requirement\n' >> PRD.md; git commit -qam 'docs: new requirement'
  git push -q --no-verify origin HEAD:main; git switch -q "$branch" )
run sync "$prd" >/dev/null
printf 'unpublished resolution\n' >> "$prd/PROGRESS.md"
git -C "$prd" commit -qam 'docs(progress): resolution' --amend
refuses "an authored merge during sync" "unverified merges" run sync "$prd"
refuses "an authored merge during cleanup" "unverified merges" \
  run merge "$prd" "docs(progress): milestone"
grep -qx 'unpublished resolution' "$prd/PROGRESS.md"

# --- creation and push outages resume without duplicate commits or hidden evidence --
fresh
touch "$tmp/fail-create"; printf 'durable row\n' >> "$prd/PROGRESS.md"
refuses "a create outage" "simulated create outage" \
  run push "$prd" "docs(progress): durable row" PROGRESS.md
oid="$(git -C "$prd" rev-parse HEAD)"; branch="$(on)"
refuses "sync hiding orphan evidence" "Progress branches exist without an open PR" run sync "$prd"
[ "$(on)" = "$branch" ]; grep -qx 'durable row' "$prd/PROGRESS.md"
rm "$tmp/fail-create"
run push "$prd" "docs(progress): durable row" PROGRESS.md >/dev/null
[ "$(git -C "$prd" rev-parse HEAD)" = "$oid" ]; [ "$(cat "$tmp/create-count")" = x ]
fresh
printf '#!/bin/sh\necho "simulated push outage" >&2\nexit 1\n' > "$tmp/origin.git/hooks/pre-receive"
chmod +x "$tmp/origin.git/hooks/pre-receive"
printf 'durable row\n' >> "$prd/PROGRESS.md"
refuses "a push outage" "simulated push outage" \
  run push "$prd" "docs(progress): durable row" PROGRESS.md
oid="$(git -C "$prd" rev-parse HEAD)"
rm "$tmp/origin.git/hooks/pre-receive"
run push "$prd" "docs(progress): durable row" PROGRESS.md >/dev/null
[ "$(git -C "$prd" rev-parse HEAD)" = "$oid" ]

# --- publication readback detects a closed batch or a concurrently changed head -----
# A stale head read right after a push is retried; a head that never matches still fails.
fresh
printf 'lagging row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): lagging row" PROGRESS.md >/dev/null
git -C "$prd" rev-parse HEAD > "$tmp/stale-head"
: > "$tmp/head-read-count"
printf 'x\nx\nx\n' > "$tmp/stale-reads"
printf 'second lagging row\n' >> "$prd/PROGRESS.md"
out="$(run push "$prd" "docs(progress): second lagging row" PROGRESS.md 2>&1)" || {
  echo "progress-pr failed on a stale head read: $out" >&2; exit 1; }
grep -q '^pr=' <<<"$out"
[ "$(cat "$tmp/head-read-count")" = xxxx ]
[ ! -s "$tmp/stale-reads" ] || { echo "stale reads were not consumed" >&2; exit 1; }
: > "$tmp/head-read-count"
printf 'x\nx\nx\nx\nx\nx\n' > "$tmp/stale-reads"
printf 'third lagging row\n' >> "$prd/PROGRESS.md"
if out="$(run push "$prd" "docs(progress): third lagging row" PROGRESS.md 2>&1)"; then
  echo "progress-pr accepted a head that never read back" >&2; exit 1
fi
[[ "$out" == *"Batch publication could not be verified"* ]]
[[ "$out" == *"head did not read back after 5 attempts"* ]]
[ "$(cat "$tmp/head-read-count")" = xxxxx ]
[ "$(cat "$tmp/stale-reads")" = x ]
rm -f "$tmp/stale-reads" "$tmp/stale-head"
for delay in -1 6 999 0.1 invalid; do
  oid="$(git -C "$prd" rev-parse HEAD)"
  refuses "invalid retry delay $delay" "PROGRESS_PR_RETRY_DELAY must be 0..5" \
    env PROGRESS_PR_RETRY_DELAY="$delay" bash "$script" \
    push "$prd" "docs(progress): invalid delay" PROGRESS.md
  [ "$(git -C "$prd" rev-parse HEAD)" = "$oid" ]
done

for race in closed merged head; do
  fresh
  printf 'reviewed row\n' >> "$prd/PROGRESS.md"
  run push "$prd" "docs(progress): reviewed row" PROGRESS.md >/dev/null
  branch="$(on)"
  printf 'durable racing row\n' >> "$prd/PROGRESS.md"
  echo "$race" > "$tmp/publish-race"
  : > "$tmp/head-read-count"
  if [ "$race" = head ]; then
    # The remote moves after accepting the push, even when the caller never reads back.
    cat > "$tmp/origin.git/hooks/post-receive" <<'HOOK'
#!/usr/bin/env bash
set -e
while read -r old new ref; do
  [ "$ref" = refs/heads/progress/batch ] || continue
  moved="$(git commit-tree "$new^{tree}" -p "$new" -m 'docs(progress): concurrent head')"
  git update-ref "$ref" "$moved" "$new"
done
HOOK
    chmod +x "$tmp/origin.git/hooks/post-receive"
  fi
  if out="$(run push "$prd" "docs(progress): racing row" PROGRESS.md 2>&1)"; then
    echo "progress-pr accepted $race during publication" >&2; exit 1
  fi
  if [ "$race" = head ]; then
    [[ "$out" == *"remote head changed"* ]]
    [ "$(cat "$tmp/head-read-count")" = x ]
  else
    [[ "$out" == *"no open batch reads back"* ]]
    [ ! -s "$tmp/head-read-count" ]
  fi
  rm -f "$tmp/publish-race"
  rm -f "$tmp/origin.git/hooks/post-receive"
  [[ "$out" == *"Batch publication could not be verified"* ]]
  [[ "$out" == *"open a PR on the preserved branch before sync"* ]]
  ! grep -q '^pr=' <<<"$out"
  oid="$(git -C "$prd" rev-parse HEAD)"
  [[ "$out" == *"$oid"* ]]
  git -C "$prd" show "$oid:PROGRESS.md" | grep -qx 'durable racing row'
  git -C "$tmp/origin.git" merge-base --is-ancestor "$oid" "$branch"
  if [ "$race" != head ]; then
    refuses "sync after $race during push" "Progress branches exist without an open PR" \
      run sync "$prd"
    if [ "$race" = merged ]; then
      refuses "push resume after a web squash" "Batch lacks origin/main" \
        run push "$prd" "docs(progress): racing row" PROGRESS.md
    fi
    # Follow the diagnostic: restore reviewability first, then import the new default.
    ( cd "$prd"; gh pr create --repo example/demo-prd --base main --head "$branch" \
      --title 'docs(progress): recover batch' --body 'Preserved tracker evidence' >/dev/null )
  fi
  if [ "$race" = merged ]; then
    refuses "sync conflict after a web squash" "merge conflict aborted" run sync "$prd"
    [[ "$out" == *"both sets of tracker evidence"* ]]
    if git -C "$prd" merge --no-edit origin/main > "$tmp/recovery-merge.log" 2>&1; then
      echo "expected a tracker conflict after the web squash" >&2; exit 1
    fi
    # The published tracker contains both the squashed row and the new evidence.
    git -C "$prd" show "$oid:PROGRESS.md" > "$prd/PROGRESS.md"
    git -C "$prd" add PROGRESS.md
    git -C "$prd" commit -qm 'docs(progress): preserve tracker evidence after web squash'
    run push "$prd" "docs(progress): recovered resolution" PROGRESS.md >/dev/null
  fi
  run sync "$prd" >/dev/null
  git -C "$prd" merge-base --is-ancestor "$oid" HEAD
  git -C "$prd" merge-base --is-ancestor origin/main HEAD
  out="$(run push "$prd" "docs(progress): recovered batch" PROGRESS.md)"
  grep -qx 'pr=7' <<<"$out"
  [ "$(cat "$tmp/open-pr")" = "7 $branch" ]
  [ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = \
    "$(git -C "$prd" rev-parse HEAD)" ]
  grep -qx 'reviewed row' "$prd/PROGRESS.md"
  grep -qx 'durable racing row' "$prd/PROGRESS.md"
done

# --- lookup outages fail closed; pagination catches old batches and late threads ----
touch "$tmp/fail-list"
refuses "a list outage" "Cannot list progress batches" run sync "$prd"
rm "$tmp/fail-list"; touch "$tmp/late-batch"
run sync "$prd" | grep -qx 'pr=7'
printf 'another row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): another row" PROGRESS.md >/dev/null
[ "$(cat "$tmp/create-count")" = x ]
touch "$tmp/fail-review"
refuses "a review outage" "Cannot read batch review state" \
  run merge "$prd" "docs(progress): milestone"
rm "$tmp/fail-review"; touch "$tmp/fail-threads"
refuses "a threads outage" "Cannot read all review threads" \
  run merge "$prd" "docs(progress): milestone"
rm "$tmp/fail-threads"; echo true > "$tmp/late-thread"
refuses "thread 101" "PRD batch awaiting review" run merge "$prd" "docs(progress): milestone"
echo false > "$tmp/late-thread"; echo true > "$tmp/draft"
refuses "a draft batch" "PRD batch awaiting review" run merge "$prd" "docs(progress): milestone"
echo false > "$tmp/draft"; echo UNKNOWN > "$tmp/merge-state"
refuses "transient provider state" "provider merge state is UNKNOWN" \
  run merge "$prd" "docs(progress): milestone"
if err="$(run merge "$prd" "docs(progress): milestone" 2>&1)"; then exit 1; fi
[[ "$err" != *"awaiting review"* ]]

# --- exact merged orphan tips are retired after a web merge; unknown work survives ---
for resume_mode in sync merge push; do
  fresh
  printf 'row\n' >> "$prd/PROGRESS.md"
  run push "$prd" "docs(progress): web batch" PROGRESS.md >/dev/null
  branch="$(on)"; oid="$(git -C "$prd" rev-parse HEAD)"
  ( cd "$prd"; gh pr merge 7 --subject 'docs(progress): web milestone (#7)' --body 'web merge' \
    --match-head-commit "$oid" )
  case "$resume_mode" in
    sync)
      refs_before="$(git -C "$tmp/origin.git" for-each-ref)"
      run sync "$prd" >/dev/null
      [ "$(git -C "$tmp/origin.git" for-each-ref)" = "$refs_before" ];;
    merge) run merge "$prd" "docs(progress): already merged" >/dev/null;;
    push)
      printf 'next row\n' >> "$prd/PROGRESS.md"
      run push "$prd" "docs(progress): next batch" PROGRESS.md >/dev/null;;
  esac
  if [ "$resume_mode" = push ]; then
    # Every new batch reuses the canonical name, but never the merged head.
    [ "$(on)" = "$branch" ]
    [ "$(git -C "$tmp/origin.git" rev-parse "$branch")" != "$oid" ]
  else
    ! git -C "$prd" show-ref --verify --quiet "refs/heads/$branch"
    if [ "$resume_mode" = sync ]; then
      [ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = "$oid" ]
      # Repeat sync, then write: the leftover merged canonical ref must not block reuse.
      run sync "$prd" >/dev/null
      printf 'after sync\n' >> "$prd/PROGRESS.md"
      run push "$prd" "docs(progress): after sync" PROGRESS.md >/dev/null
      [ "$(on)" = "$branch" ]
      [ "$(git -C "$tmp/origin.git" rev-parse "$branch")" != "$oid" ]
    else
      ! git -C "$tmp/origin.git" show-ref --verify --quiet "refs/heads/$branch"
    fi
  fi
  if [ "$resume_mode" = push ]; then [ "$(cat "$tmp/create-count")" = xx ]; fi
  grep -qx 'row' "$prd/PROGRESS.md"
done
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): web batch" PROGRESS.md >/dev/null
branch="$(on)"; oid="$(git -C "$prd" rev-parse HEAD)"
( cd "$prd"; gh pr merge 7 --subject 'docs(progress): web milestone (#7)' --body 'web merge' \
  --match-head-commit "$oid" )
printf 'unmerged work\n' >> "$prd/PROGRESS.md"
git -C "$prd" commit -qam 'docs(progress): unpublished'
refuses "an advanced local orphan" "unexplained tips" run sync "$prd"
grep -qx 'unmerged work' "$prd/PROGRESS.md"
git -C "$prd" show-ref --verify --quiet "refs/heads/$branch"

# --- classifications and dependency/default recovery messages are actionable -------
fresh
printf 'local default work\n' >> "$prd/PROGRESS.md"
git -C "$prd" commit -qam 'docs(progress): local default work'
refuses "default-branch local commits" "move them onto a branch and open a pull request" run sync "$prd"
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): row" PROGRESS.md >/dev/null
for state in DIRTY BEHIND BLOCKED DRAFT UNKNOWN; do
  echo "$state" > "$tmp/merge-state"
  code=0; err="$(run merge "$prd" "docs(progress): milestone" 2>&1)" || code=$?
  case "$state" in
    DIRTY) [ "$code" = 1 ]; [[ "$err" == *"merge conflict"* && "$err" != *"awaiting review"* ]];;
    BEHIND) [ "$code" = 1 ]; [[ "$err" == *"requires a base update"* && "$err" != *"awaiting review"* ]];;
    BLOCKED) [ "$code" = 1 ]; [[ "$err" == *"inspect branch rules"* ]];;
    DRAFT) [ "$code" = 2 ]; [[ "$err" == *"PRD batch awaiting review"* ]];;
    UNKNOWN) [ "$code" = 1 ]; [[ "$err" == *"provider merge state"* && "$err" != *"awaiting review"* ]];;
  esac
done
# An isolated PATH really has no jq; the provider fixture itself does not need jq.
mkdir -p "$tmp/no-jq-bin"
for executable in bash git dirname mktemp cat chmod mkdir cmp grep tr rm; do
  ln -s "$(command -v "$executable")" "$tmp/no-jq-bin/$executable"
done
cat > "$tmp/no-jq-bin/gh" <<'NOJQ'
#!/bin/bash
if [ "$1 $2" = 'repo view' ]; then
  [[ "$*" == *nameWithOwner* ]] && echo example/demo-prd || echo main
else echo '[[]]'; fi
NOJQ
chmod +x "$tmp/no-jq-bin/gh"
refuses "missing jq" "Missing dependency: jq; install jq before retrying" env PATH="$tmp/no-jq-bin" bash "$script" sync "$prd"

# --- UNKNOWN retries refresh the complete snapshot, with a strict bound ------------
for effect in none head draft requested latest checks threads; do
  fresh
  printf 'row\n' >> "$prd/PROGRESS.md"
  run push "$prd" "docs(progress): pending provider state" PROGRESS.md >/dev/null
  printf 'UNKNOWN\nUNKNOWN\nCLEAN\n' > "$tmp/snapshot-sequence"
  echo "$effect" > "$tmp/snapshot-effect"
  case "$effect" in
    none|head)
      run merge "$prd" "docs(progress): settled milestone" >/dev/null
      [ "$(cat "$tmp/merge-count")" = x ]
      if [ "$effect" = head ]; then cmp "$tmp/snapshot-expected-head" "$tmp/pr-merged-head"; fi;;
    checks)
      code=0; err="$(run merge "$prd" 'docs(progress): settled milestone' 2>&1)" || code=$?
      [ "$code" = 1 ]; [[ "$err" == *"check blocker: ci"* ]]
      [ ! -f "$tmp/merge-count" ];;
    *) refuses "a refreshed $effect gate" "PRD batch awaiting review" \
      run merge "$prd" "docs(progress): settled milestone";;
  esac
  [ "$(cat "$tmp/snapshot-count")" = 3 ]
done
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): persistent unknown" PROGRESS.md >/dev/null
echo UNKNOWN > "$tmp/merge-state"
code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
[ "$code" = 1 ]; [[ "$err" == *"UNKNOWN after 5 snapshots"* && "$err" != *"awaiting review"* ]]
[ "$(cat "$tmp/snapshot-count")" = 5 ]; [ ! -f "$tmp/merge-count" ]
echo CLEAN > "$tmp/merge-state"; touch "$tmp/advance-after-snapshot"
refuses "a head advanced after the snapshot" "Head branch was modified" \
  run merge "$prd" "docs(progress): milestone"

# --- reviews or checks beyond the evaluated provider page fail closed --------------
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): counted row" PROGRESS.md >/dev/null
echo 101 > "$tmp/review-total"
refuses "reviews beyond one page" "more reviews or checks than one provider page" \
  run merge "$prd" "docs(progress): milestone"
rm "$tmp/review-total"; echo 101 > "$tmp/check-total"
refuses "checks beyond one page" "more reviews or checks than one provider page" \
  run merge "$prd" "docs(progress): milestone"
rm "$tmp/check-total"; touch "$tmp/advance-before-counts"
refuses "a head moved before the count" "or its head moved" \
  run merge "$prd" "docs(progress): milestone"
rm "$tmp/advance-before-counts"
run merge "$prd" "docs(progress): counted milestone" >/dev/null
[ "$(cat "$tmp/merge-count")" = x ] || { echo "complete totals must still merge" >&2; exit 1; }

# --- a later comment cannot hide an outstanding change request ----------------------
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): commented row" PROGRESS.md >/dev/null
echo '[{"author":{"login":"maintainer"},"state":"COMMENTED"}]' > "$tmp/latest-reviews"
echo '[{"author":{"login":"maintainer"},"state":"CHANGES_REQUESTED"}]' > "$tmp/opinionated-reviews"
code=0; err="$(run merge "$prd" 'docs(progress): milestone' 2>&1)" || code=$?
[ "$code" = 2 ] && [[ "$err" == *"has requested changes"* ]] || {
  echo "a comment after a change request must still refuse with exit 2: $code $err" >&2; exit 1; }
[ ! -f "$tmp/merge-count" ]
echo 101 > "$tmp/opinionated-total"
refuses "opinionated reviews beyond one page" "more reviews or checks than one provider page" \
  run merge "$prd" "docs(progress): milestone"
rm "$tmp/opinionated-total"
echo '[{"author":{"login":"maintainer"},"state":"APPROVED"}]' > "$tmp/opinionated-reviews"
run merge "$prd" "docs(progress): approved after comment" >/dev/null
[ "$(cat "$tmp/merge-count")" = x ] || { echo "an approval must clear the change request" >&2; exit 1; }

# --- mechanical imports ignore ff-only/squash configuration and clean up failures --
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): initial row" PROGRESS.md >/dev/null
branch="$(on)"
( cd "$prd"; git switch -q --detach origin/main
  printf 'new requirement\n' >> PRD.md; git commit -qam 'docs: new requirement'
  git push -q --no-verify origin HEAD:main; git switch -q "$branch" )
git -C "$prd" config merge.ff only
git -C "$prd" config "branch.$branch.mergeOptions" '--squash --no-commit -s ours'
git -C "$prd" config commit.gpgSign true
git -C "$prd" config gpg.program /nonexistent-idd-test-signer
remote_before="$(git -C "$tmp/origin.git" rev-parse "$branch")"
run sync "$prd" >/dev/null
grep -qx 'new requirement' "$prd/PRD.md"
[ -z "$(git -C "$prd" status --porcelain)" ]
[ "$(git -C "$tmp/origin.git" rev-parse "$branch")" = "$remote_before" ]
run sync "$prd" >/dev/null

# Simulate a non-conflict Git failure that modifies a tracked file but creates no merge state.
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): initial row" PROGRESS.md >/dev/null
before="$(git -C "$prd" rev-parse HEAD)"
real_git="$(command -v git)"; export PROGRESS_TEST_REAL_GIT="$real_git"
cat > "$tmp/bin/git" <<'GIT'
#!/bin/bash
if [[ "$*" == *'--no-edit'* ]]; then
  printf 'failed operation dirt\n' >> PRD.md
  echo 'simulated Git operation failure' >&2
  exit 1
fi
exec "$PROGRESS_TEST_REAL_GIT" "$@"
GIT
chmod +x "$tmp/bin/git"
refuses "a non-conflict merge failure" "merge operation failed without conflict" run sync "$prd"
rm "$tmp/bin/git"
[ "$(git -C "$prd" rev-parse HEAD)" = "$before" ]
[ -z "$(git -C "$prd" status --porcelain)" ]
! git -C "$prd" rev-parse -q --verify MERGE_HEAD >/dev/null

# --- reverted non-tracker edits in merge commits cannot hide in batch history ------
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): row" PROGRESS.md >/dev/null
( cd "$prd"
  before="$(git rev-parse HEAD)"
  printf 'contract smuggled in merge\n' >> PRD.md; git add PRD.md
  bad="$(git commit-tree "$(git write-tree)" -p "$before" -p origin/main -m 'merge: smuggle contract')"
  restored="$(git commit-tree "$before^{tree}" -p "$bad" -p origin/main -m 'merge: hide contract diff')"
  git reset -q --hard "$restored"
)
printf 'next row\n' >> "$prd/PROGRESS.md"
refuses "non-tracker merge history" "Non-tracker path in batch: PRD.md" \
  run push "$prd" "docs(progress): next row" PROGRESS.md
git -C "$prd" checkout -q -- .
git -C "$prd" push -q origin HEAD
refuses "published non-tracker merge history" "Non-tracker path in batch: PRD.md" \
  run merge "$prd" "docs(progress): milestone"

# Git omits remerge diffs for octopus merges; they must fail closed rather than hide edits.
fresh
printf 'row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): row" PROGRESS.md >/dev/null
( cd "$prd"
  before="$(git rev-parse HEAD)"
  side="$(git commit-tree 'origin/main^{tree}' -p origin/main -m 'docs(progress): side')"
  octopus="$(git commit-tree "$before^{tree}" -p "$before" -p origin/main -p "$side" -m 'merge: octopus')"
  git reset -q --hard "$octopus"
)
printf 'next row\n' >> "$prd/PROGRESS.md"
refuses "an octopus history blind spot" "Unsupported octopus merge in batch" \
  run push "$prd" "docs(progress): next row" PROGRESS.md

# --- a commit hook cannot add non-tracker content after the index check ------------
for hook in pre-commit post-commit; do
  fresh
  cat > "$prd/.git/hooks/$hook" <<'HOOK'
#!/bin/sh
printf 'hook contract edit\n' >> PRD.md
git add PRD.md
if [ "${0##*/}" = post-commit ]; then
  rm "$0"
  git commit -q --amend --no-edit
fi
HOOK
  chmod +x "$prd/.git/hooks/$hook"
  printf 'hook tracker evidence\n' >> "$prd/PROGRESS.md"
  refuses "$hook contamination" "remains unpublished" \
    run push "$prd" "docs(progress): hooked evidence" PROGRESS.md
  git -C "$prd" show HEAD:PROGRESS.md | grep -qx 'hook tracker evidence'
  git -C "$prd" show HEAD:PRD.md | grep -qx 'hook contract edit'
  [ -z "$(git -C "$tmp/origin.git" for-each-ref refs/heads/progress/)" ]
  [ ! -f "$tmp/create-count" ]
done

# --- two clones reach their first push together: one canonical batch survives ------
# An old orphan keeps its evidence but must adopt the canonical name before creating a PR.
fresh
git -C "$prd" switch -q -c progress/legacy
printf 'legacy evidence\n' >> "$prd/PROGRESS.md"
git -C "$prd" commit -qam 'docs(progress): legacy row'
refuses "a legacy orphan creating another head" "Legacy orphan progress/legacy" \
  run push "$prd" "docs(progress): legacy row" PROGRESS.md
git -C "$prd" show HEAD:PROGRESS.md | grep -qx 'legacy evidence'
git -C "$prd" branch -m progress/batch
run push "$prd" "docs(progress): legacy row" PROGRESS.md >/dev/null

# Already-open legacy batches still sync, accumulate, and merge normally.
fresh
git -C "$prd" switch -q -c progress/legacy
printf 'legacy evidence\n' >> "$prd/PROGRESS.md"
git -C "$prd" commit -qam 'docs(progress): legacy row'
git -C "$prd" push -q origin HEAD
echo '7 progress/legacy' > "$tmp/open-pr"; echo progress/legacy > "$tmp/pr-head"
run sync "$prd" >/dev/null
printf 'next legacy row\n' >> "$prd/PROGRESS.md"
run push "$prd" "docs(progress): next legacy row" PROGRESS.md >/dev/null
run merge "$prd" "docs(progress): legacy milestone" >/dev/null
grep -qx 'next legacy row' "$prd/PROGRESS.md"

real_git="$(command -v git)"; export PROGRESS_TEST_REAL_GIT="$real_git"
for race in divergent identical; do
  fresh
  rm -rf "$tmp/second-prd" "$tmp/race"
  mkdir "$tmp/race"
  git clone -q "$tmp/origin.git" "$tmp/second-prd"
  printf 'winner evidence\n' >> "$prd/PROGRESS.md"
  if [ "$race" = identical ]; then
    cp "$prd/PROGRESS.md" "$tmp/second-prd/PROGRESS.md"
  else printf 'other evidence\n' >> "$tmp/second-prd/PROGRESS.md"; fi
  # Distinct start seconds reproduce the old timestamp-name race deterministically.
  cat > "$tmp/bin/date" <<'DATE'
#!/bin/sh
case "${PWD##*/}" in demo-prd) echo 20260911-000001;; *) echo 20260911-000002;; esac
DATE
  chmod +x "$tmp/bin/date"
  cat > "$tmp/bin/git" <<'GIT'
#!/bin/bash
if [ "$1" = push ]; then
  # Both invocations have already fetched and observed no open PR before either pushes.
  touch "$PROGRESS_TEST_ROOT/race/${PWD##*/}"
  for attempt in {1..200}; do
    if [ -f "$PROGRESS_TEST_ROOT/race/demo-prd" ] &&
      [ -f "$PROGRESS_TEST_ROOT/race/second-prd" ]; then
      if [ "${PWD##*/}" = demo-prd ]; then
        "$PROGRESS_TEST_REAL_GIT" "$@"; code=$?
        touch "$PROGRESS_TEST_ROOT/race/first-pushed"
        exit "$code"
      elif [ -f "$PROGRESS_TEST_ROOT/race/first-pushed" ]; then
        exec "$PROGRESS_TEST_REAL_GIT" "$@"
      fi
    fi
    sleep 0.05
  done
  echo 'race barrier timed out' >&2; exit 1
fi
exec "$PROGRESS_TEST_REAL_GIT" "$@"
GIT
  chmod +x "$tmp/bin/git"
  export GIT_AUTHOR_DATE='2026-09-11T00:00:00Z' GIT_COMMITTER_DATE='2026-09-11T00:00:00Z'
  run push "$prd" "docs(progress): racing row" PROGRESS.md > "$tmp/race/one.out" 2>&1 &
  one=$!
  run push "$tmp/second-prd" "docs(progress): racing row" PROGRESS.md \
    > "$tmp/race/two.out" 2>&1 &
  two=$!
  one_code=0; wait "$one" || one_code=$?
  two_code=0; wait "$two" || two_code=$?
  unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
  rm "$tmp/bin/git" "$tmp/bin/date"
  if [ "$one_code $two_code" = '0 1' ]; then loser=two; else
    [ "$one_code $two_code" = '1 0' ] || {
      cat "$tmp/race/one.out" "$tmp/race/two.out" >&2; exit 1; }
    loser=one
  fi
  if [ "$race" = divergent ]; then
    grep -q 'Batch push failed; local commit .* is preserved' "$tmp/race/$loser.out"
  else grep -q 'Batch PR creation failed; .* is preserved' "$tmp/race/$loser.out"; fi
  grep -q 'rerun reconcile' "$tmp/race/$loser.out"
  [ "$(cat "$tmp/create-count")" = x ]
  [ "$(cat "$tmp/open-pr")" = '7 progress/batch' ]
  [ "$(git -C "$tmp/origin.git" for-each-ref --format='%(refname)' refs/heads/progress/)" \
    = refs/heads/progress/batch ]
  git -C "$prd" show HEAD:PROGRESS.md | grep -qx 'winner evidence'
  if [ "$race" = divergent ]; then
    git -C "$tmp/second-prd" show HEAD:PROGRESS.md | grep -qx 'other evidence'
  fi
done

echo "IDD progress batch valid"
