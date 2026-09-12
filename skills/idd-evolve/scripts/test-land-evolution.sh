#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/skills/idd-evolve/scripts/land-evolution.sh"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$tmp/bin"
export LANDEV_TEST_ROOT="$tmp"
export PATH="$tmp/bin:$PATH"

# The fake gh answers PR fields from state files and performs a real squash on
# merge: one commit-tree of the head onto origin/main, pushed to main, and the
# head branch deleted unless LANDEV_TEST_KEEP_REMOTE simulates that setting off.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${LANDEV_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then
  [[ "$*" == *nameWithOwner* ]] && echo example/demo || echo main
elif [ "$1 $2" = "pr view" ]; then
  key="${*: -1}"
  case "$key" in
    .state) cat "$root/pr-state";;
    .baseRefName) cat "$root/pr-base";;
    .headRefName) cat "$root/pr-head";;
    .isDraft) cat "$root/pr-draft";;
    .isCrossRepository) echo false;;
    .title) cat "$root/pr-title";;
    .mergeStateStatus) cat "$root/pr-merge-state";;
    '.body // ""') cat "$root/pr-body";;
    '.mergeCommit.oid // ""') [ -f "$root/merge-oid" ] && cat "$root/merge-oid" || true;;
    .headRefOid) cat "$root/pr-head-oid";;
    *) echo "unexpected pr view key: $key" >&2; exit 2;;
  esac
elif [ "$1 $2" = "pr merge" ]; then
  subject=""; body=""; match=""
  while [ "$#" -gt 0 ]; do
    case "$1" in --subject) subject="$2"; shift;; --body) body="$2"; shift;; --match-head-commit) match="$2"; shift;; esac
    shift
  done
  [ -z "${LANDEV_TEST_WRONG_SUBJECT:-}" ] || subject="$LANDEV_TEST_WRONG_SUBJECT"
  head="$(cat "$root/pr-head")"
  git fetch -q origin
  # GitHub refuses the merge when the head no longer matches the required commit.
  [ -n "$match" ] || { echo "merge without --match-head-commit" >&2; exit 1; }
  [ "$match" = "$(git rev-parse "origin/$head")" ] || { echo "GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)" >&2; exit 1; }
  tree="$(git rev-parse "origin/$head^{tree}")"
  # GitHub takes an explicit subject verbatim: no " (#N)" is appended here.
  oid="$(git commit-tree "$tree" -p "$(git rev-parse origin/main)" -m "$subject" -m "$body")"
  git push -q origin "$oid:main"
  [ -n "${LANDEV_TEST_KEEP_REMOTE:-}" ] || git push -q origin --delete "$head"
  echo "$oid" > "$root/merge-oid"; echo MERGED > "$root/pr-state"; printf 'x' >> "$root/merge-count"
elif [ "$1" = api ]; then
  oid="${2##*/}"; key="${*: -1}"
  case "$key" in
    '.parents | length') git fetch -q origin; git rev-list --parents -n1 "$oid" | wc -w | awk '{print $1-1}';;
    .commit.message) git fetch -q origin; git log -1 --format=%B "$oid";;
    *) echo "unexpected api key: $key" >&2; exit 2;;
  esac
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"

fresh() { # origin with main plus a one-commit evolve branch, a clone on main holding that branch too
  rm -rf "$tmp/origin.git" "$tmp/work" "$tmp"/pr-* "$tmp"/merge-*
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
  ( cd "$tmp/work"; git switch -q -c main 2>/dev/null || true
    printf 'a\n' > a.txt; git add a.txt; git commit -qm "chore: init"; git push -q -u origin main
    git switch -q -c evolve/reviewed; printf 'a2\n' > a.txt; printf 'z\n' > z.txt; git add a.txt z.txt
    git commit -qm "evolve: route kept evolutions through pull requests"; git push -q -u origin evolve/reviewed
    git switch -q main )
  echo OPEN > "$tmp/pr-state"; echo main > "$tmp/pr-base"; echo evolve/reviewed > "$tmp/pr-head"; echo false > "$tmp/pr-draft"
  git -C "$tmp/work" rev-parse evolve/reviewed > "$tmp/pr-head-oid"
  git -C "$tmp/origin.git" update-ref refs/pull/5/head "$(cat "$tmp/pr-head-oid")"
  printf 'evolve: route kept evolutions through pull requests' > "$tmp/pr-title"; echo CLEAN > "$tmp/pr-merge-state"
  printf 'Evidence: reviewed.\n\nKept: one branch.' > "$tmp/pr-body"
}
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "land-evolution accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "land-evolution rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
  [ ! -f "$tmp/merge-count" ] || { echo "a refused landing must not merge ($desc)" >&2; exit 1; }
}
run() { (cd "$tmp/work" && bash "$script" 5); }

# --- the happy path from main -----------------------------------------------------
fresh
out="$(run)"
case "$out" in "landed example/demo#5 as "*": evolve: route kept evolutions through pull requests (#5)") ;; *) echo "unexpected output: $out" >&2; exit 1;; esac
[ "$(git -C "$tmp/work" symbolic-ref --short HEAD)" = main ] || { echo "must end on main" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "local main must equal the landed origin main" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-list --count HEAD)" = 2 ] || { echo "the squash must add exactly one commit" >&2; exit 1; }
[ "$(git -C "$tmp/work" log -1 --format=%B)" = "$(printf 'evolve: route kept evolutions through pull requests (#5)\n\nEvidence: reviewed.\n\nKept: one branch.')" ] || { echo "landed message must be the PR title and body" >&2; exit 1; }
[ "$(cat "$tmp/work/z.txt")" = z ] || { echo "landed content must be checked out" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "local evolve branch must be deleted" >&2; exit 1; }
! git -C "$tmp/origin.git" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "origin evolve branch must be deleted" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/remotes/origin/evolve/reviewed || { echo "the stale remote-tracking ref must be pruned" >&2; exit 1; }

# --- from the evolve branch itself, and when the provider leaves the branch behind --
fresh; git -C "$tmp/work" switch -q evolve/reviewed
LANDEV_TEST_KEEP_REMOTE=1 run >/dev/null
[ "$(git -C "$tmp/work" symbolic-ref --short HEAD)" = main ] || { echo "must switch to main before deleting the branch" >&2; exit 1; }
! git -C "$tmp/origin.git" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the script must delete a remote branch the provider kept" >&2; exit 1; }

# The PR head may have been pushed from another clone: the local branch is an
# ancestor whose newer objects are absent here until the pull ref is fetched.
fresh
git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null; git -C "$tmp/other" switch -q evolve/reviewed
printf 'fix\n' > "$tmp/other/fix.txt"; git -C "$tmp/other" add fix.txt; git -C "$tmp/other" commit -qm "fix: review follow-up"; git -C "$tmp/other" push -q origin evolve/reviewed
git -C "$tmp/other" rev-parse HEAD > "$tmp/pr-head-oid"; git -C "$tmp/origin.git" update-ref refs/pull/5/head "$(cat "$tmp/pr-head-oid")"; rm -rf "$tmp/other"
! git -C "$tmp/work" cat-file -e "$(cat "$tmp/pr-head-oid")" 2>/dev/null || { echo "fixture must lack the other clone's commit" >&2; exit 1; }
run >/dev/null 2>&1
[ "$(cat "$tmp/work/fix.txt")" = fix ] || { echo "a head pushed from another clone must land" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the ancestor local branch must be deleted" >&2; exit 1; }

# A branch replaced between the lookup and the delete survives: the delete is lease-protected.
fresh; real_git="$(command -v git)"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = ls-remote ] && [ -n "\${LANDEV_TEST_STALE_TIP:-}" ]; then printf '%s\trefs/heads/evolve/reviewed\n' "\$LANDEV_TEST_STALE_TIP"; exit 0; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
(cd "$tmp/work" && gh pr merge 5 --repo example/demo --squash --match-head-commit "$(cat "$tmp/pr-head-oid")" --subject "evolve: route kept evolutions through pull requests (#5)" --body "$(cat "$tmp/pr-body")")
git -C "$tmp/work" switch -q evolve/reviewed; printf 'race\n' > "$tmp/work/race.txt"; git -C "$tmp/work" add race.txt; git -C "$tmp/work" commit -qm "evolve: replaced during landing"
git -C "$tmp/work" push -q origin evolve/reviewed; git -C "$tmp/work" switch -q main; git -C "$tmp/work" branch -q -D evolve/reviewed
replaced="$(git -C "$tmp/origin.git" rev-parse evolve/reviewed)"
if out="$(LANDEV_TEST_STALE_TIP="$(cat "$tmp/pr-head-oid")" run 2>&1)"; then echo "a branch replaced after the lookup must not be deleted" >&2; exit 1; fi
case "$out" in *"moved while landing"*) ;; *) echo "wrong diagnostic for a replaced branch: $out" >&2; exit 1;; esac
[ "$(git -C "$tmp/origin.git" rev-parse evolve/reviewed)" = "$replaced" ] || { echo "the replaced remote branch must survive the lease" >&2; exit 1; }
rm -f "$tmp/bin/git" "$tmp/merge-count"

# A head pushed after the checks must fail the merge instead of landing unreviewed.
fresh
git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null; git -C "$tmp/other" switch -q evolve/reviewed
printf 'late\n' > "$tmp/other/late.txt"; git -C "$tmp/other" add late.txt; git -C "$tmp/other" commit -qm "evolve: pushed after the checks"; git -C "$tmp/other" push -q origin evolve/reviewed; rm -rf "$tmp/other"
refuses "a head that moved after validation" "Head branch was modified" run
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 1 ] || { echo "a mismatched head must not land" >&2; exit 1; }

# A local branch checked out in another worktree is never deleted from under it.
fresh; git -C "$tmp/work" worktree add -q "$tmp/wt" evolve/reviewed
if out="$(LANDEV_TEST_KEEP_REMOTE=1 run 2>&1)"; then echo "a branch checked out in a worktree must not be deleted" >&2; exit 1; fi
case "$out" in *"checked out in another worktree"*) ;; *) echo "wrong diagnostic for a worktree branch: $out" >&2; exit 1;; esac
git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the worktree branch must survive" >&2; exit 1; }
[ "$(git -C "$tmp/wt" symbolic-ref --short HEAD)" = evolve/reviewed ] || { echo "the worktree must keep its branch" >&2; exit 1; }
git -C "$tmp/work" worktree remove --force "$tmp/wt"; rm -f "$tmp/merge-count"

# The worktree guard fails closed: an unreadable inventory refuses, and a huge inventory still finds the branch.
fresh; real_git="$(command -v git)"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = worktree ] && [ "\$2" = list ]; then echo "fatal: simulated worktree failure" >&2; exit 128; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
if out="$(LANDEV_TEST_KEEP_REMOTE=1 run 2>&1)"; then echo "an unreadable worktree list must refuse the delete" >&2; exit 1; fi
case "$out" in *"Cannot read the worktree list"*) ;; *) echo "wrong diagnostic for a failed worktree list: $out" >&2; exit 1;; esac
git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the branch must survive a failed inventory" >&2; exit 1; }
rm -f "$tmp/bin/git" "$tmp/merge-count"
fresh
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = worktree ] && [ "\$2" = list ]; then
  awk 'BEGIN { for (i=0; i<100000; i++) printf "worktree /w%d\\nHEAD 0000000000000000000000000000000000000000\\nbranch refs/heads/other%d\\n\\n", i, i; print "worktree /held"; print "HEAD 0000000000000000000000000000000000000000"; print "branch refs/heads/evolve/reviewed"; print "" }'
  exit 0
fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
if out="$(LANDEV_TEST_KEEP_REMOTE=1 run 2>&1)"; then echo "a branch listed late in a huge inventory must still be protected" >&2; exit 1; fi
case "$out" in *"checked out in another worktree"*) ;; *) echo "wrong diagnostic for a huge inventory: $out" >&2; exit 1;; esac
git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the branch must survive a huge inventory" >&2; exit 1; }
rm -f "$tmp/bin/git" "$tmp/merge-count"

# A local branch that moved or appeared after the ancestry check is never deleted.
race_git() { # $1 = action performed right after the real `git pull` (between check and delete)
  cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = pull ]; then "$real_git" "\$@"; rc=\$?; $1; exit \$rc; fi
exec "$real_git" "\$@"
FAKE
  chmod +x "$tmp/bin/git"
}
fresh; real_git="$(command -v git)"
race_git "\"$real_git\" update-ref refs/heads/evolve/reviewed \$(\"$real_git\" commit-tree HEAD^{tree} -p refs/heads/evolve/reviewed -m 'evolve: advanced during landing')"
if out="$(LANDEV_TEST_KEEP_REMOTE=1 run 2>&1)"; then echo "a local branch advanced during landing must not be deleted" >&2; exit 1; fi
case "$out" in *"local evolve/reviewed moved while landing"*) ;; *) echo "wrong diagnostic for an advanced local branch: $out" >&2; exit 1;; esac
git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the advanced local branch must survive" >&2; exit 1; }
[ "$(git -C "$tmp/work" log -1 --format=%s evolve/reviewed)" = "evolve: advanced during landing" ] || { echo "the advanced tip must be intact" >&2; exit 1; }
rm -f "$tmp/bin/git" "$tmp/merge-count"
fresh; git -C "$tmp/work" branch -q -D evolve/reviewed
race_git "\"$real_git\" branch evolve/reviewed origin/main"
if out="$(LANDEV_TEST_KEEP_REMOTE=1 run 2>&1)"; then echo "a local branch created during landing must not be deleted" >&2; exit 1; fi
case "$out" in *"local evolve/reviewed appeared while landing"*) ;; *) echo "wrong diagnostic for a recreated local branch: $out" >&2; exit 1;; esac
git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "the recreated local branch must survive" >&2; exit 1; }
rm -f "$tmp/bin/git" "$tmp/merge-count"

# Reading only the subject must still drain a large API response under pipefail.
fresh
awk 'BEGIN { for (i=0; i<20000; i++) print "body" }' > "$tmp/pr-body"
run >/dev/null 2>&1

# --- refusals leave everything untouched --------------------------------------------
fresh; echo CLOSED > "$tmp/pr-state"; refuses "a closed PR" "is CLOSED, not OPEN" run
fresh; echo MERGED > "$tmp/pr-state"; refuses "a merged PR without a merge commit" "reports no merge commit" run
fresh; echo develop > "$tmp/pr-base"; refuses "a PR onto another base" "targets develop, not main" run
fresh; echo issue/3-fix > "$tmp/pr-head"; refuses "a non-evolve head" "not an evolve/<slug> branch (N-3)" run
fresh; echo true > "$tmp/pr-draft"; refuses "a draft" "is a draft" run
fresh; printf 'Route kept evolutions through pull requests' > "$tmp/pr-title"; refuses "an untyped title" "must be an N-4 subject" run
fresh; printf 'evolve: %s' "$(printf 'x%.0s' $(seq 1 70))" > "$tmp/pr-title"; refuses "a long title" "exceeds 72" run
fresh; echo BLOCKED > "$tmp/pr-merge-state"; refuses "a blocked PR" "resolve every review thread" run
fresh; echo DIRTY > "$tmp/pr-merge-state"; refuses "a conflicting PR" "conflicts with main" run
fresh; echo UNKNOWN > "$tmp/pr-merge-state"; refuses "an uncomputed merge state" "not CLEAN" run
fresh; printf 'dirty\n' > "$tmp/work/a.txt"; refuses "a dirty working tree" "dirty working tree" run
refuses "a non-numeric PR" "usage:" bash -c "cd '$tmp/work' && bash '$script' abc"
fresh; refuses "an unreadable index" "Cannot read the working tree state" env GIT_INDEX_FILE=/dev/null bash -c "cd '$tmp/work' && bash '$script' 5"
[ "$(git -C "$tmp/origin.git" rev-list --count main)" = 1 ] || { echo "refusals must leave origin main alone" >&2; exit 1; }

# A clean local evolve branch may still contain work absent from the PR.
fresh
git -C "$tmp/work" switch -q evolve/reviewed
git -C "$tmp/work" commit -q --allow-empty -m "fix: keep local work"
refuses "unpushed evolve commits" "local commits absent from the PR head" run

# --- a landed subject that differs from the title is disclosed after the merge --------
fresh
if err="$(cd "$tmp/work" && LANDEV_TEST_WRONG_SUBJECT='wrong subject' bash "$script" 5 2>&1 >/dev/null)"; then echo "a wrong landed subject must fail" >&2; exit 1; fi
case "$err" in *"Landed subject is 'wrong subject', expected 'evolve: route kept evolutions through pull requests (#5)'"*) ;; *) echo "wrong reason for a wrong landed subject: $err" >&2; exit 1;; esac

# --- a landing that failed after the merge resumes: cleanup only, no second merge ---
fresh
(cd "$tmp/work" && gh pr merge 5 --repo example/demo --squash --match-head-commit "$(cat "$tmp/pr-head-oid")" --subject "evolve: route kept evolutions through pull requests (#5)" --body "$(cat "$tmp/pr-body")")
[ "$(cat "$tmp/pr-state")" = MERGED ] && git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "resume fixture must be merged with the local branch left behind" >&2; exit 1; }
out="$(run 2>"$tmp/resume-err")"
case "$out" in "landed example/demo#5 as "*) ;; *) echo "resume must report the landing: $out" >&2; exit 1;; esac
grep -q "already MERGED; resuming" "$tmp/resume-err" || { echo "resume must disclose that it skipped the merge" >&2; exit 1; }
[ "$(cat "$tmp/merge-count")" = x ] || { echo "resume must not merge a second time" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "resume must fast-forward main" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "resume must delete the local evolve branch" >&2; exit 1; }
# A resumed landing succeeds after other landings moved main past the squash commit.
fresh
(cd "$tmp/work" && gh pr merge 5 --repo example/demo --squash --match-head-commit "$(cat "$tmp/pr-head-oid")" --subject "evolve: route kept evolutions through pull requests (#5)" --body "$(cat "$tmp/pr-body")")
landed_oid="$(cat "$tmp/merge-oid")"
git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null; printf 'later\n' > "$tmp/other/later.txt"; git -C "$tmp/other" add later.txt; git -C "$tmp/other" commit -qm "evolve: land something later (#6)"; git -C "$tmp/other" push -q origin main; rm -rf "$tmp/other"
run >/dev/null 2>&1
[ "$(git -C "$tmp/work" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "resume must fast-forward to origin's current main" >&2; exit 1; }
git -C "$tmp/work" merge-base --is-ancestor "$landed_oid" HEAD || { echo "resume must keep the landed commit reachable" >&2; exit 1; }
! git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "resume after later landings must still delete the local branch" >&2; exit 1; }
# A resumed landing never deletes a remote branch that is no longer the PR head.
fresh
(cd "$tmp/work" && gh pr merge 5 --repo example/demo --squash --match-head-commit "$(cat "$tmp/pr-head-oid")" --subject "evolve: route kept evolutions through pull requests (#5)" --body "$(cat "$tmp/pr-body")")
git -C "$tmp/work" switch -q evolve/reviewed; printf 'new\n' > "$tmp/work/new.txt"; git -C "$tmp/work" add new.txt; git -C "$tmp/work" commit -qm "evolve: someone recreated the branch"
git -C "$tmp/work" push -q origin evolve/reviewed; git -C "$tmp/work" switch -q main; git -C "$tmp/work" branch -q -D evolve/reviewed
recreated="$(git -C "$tmp/origin.git" rev-parse evolve/reviewed)"
if out="$(run 2>&1)"; then echo "a recreated remote branch must not be deleted silently" >&2; exit 1; fi
case "$out" in *"origin/evolve/reviewed is at $recreated, not the PR head"*) ;; *) echo "wrong diagnostic for a recreated remote branch: $out" >&2; exit 1;; esac
[ "$(git -C "$tmp/origin.git" rev-parse evolve/reviewed)" = "$recreated" ] || { echo "the recreated remote branch must survive" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-parse HEAD)" = "$(git -C "$tmp/origin.git" rev-parse main)" ] || { echo "the local landing steps must still complete before the remote refusal" >&2; exit 1; }
rm -f "$tmp/merge-count"
# A resumed landing still refuses to delete local work the PR never carried.
fresh
(cd "$tmp/work" && gh pr merge 5 --repo example/demo --squash --match-head-commit "$(cat "$tmp/pr-head-oid")" --subject "evolve: route kept evolutions through pull requests (#5)" --body "$(cat "$tmp/pr-body")")
rm -f "$tmp/merge-count"
git -C "$tmp/work" switch -q evolve/reviewed; git -C "$tmp/work" commit -q --allow-empty -m "fix: keep local work"; git -C "$tmp/work" switch -q main
refuses "resumed landing over unpushed evolve commits" "local commits absent from the PR head" run
git -C "$tmp/work" show-ref --verify --quiet refs/heads/evolve/reviewed || { echo "a refused resume must keep the local branch" >&2; exit 1; }

# Remote lookup failure is not evidence that cleanup succeeded.
fresh
real_git="$(command -v git)"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = ls-remote ]; then echo "simulated transport error" >&2; exit 128; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
if out="$(LANDEV_TEST_KEEP_REMOTE=1 run 2>&1)"; then echo "landing reported success despite failed remote lookup" >&2; exit 1; fi
case "$out" in *"Cannot verify origin branch"*) ;; *) echo "wrong remote lookup diagnostic: $out" >&2; exit 1;; esac
rm -f "$tmp/bin/git"

# --- the shared line width -------------------------------------------------------
# A review fix pushed after proposing still answers to the width before it lands.
fresh
( cd "$tmp/work"; git switch -q evolve/reviewed; printf '%0101d\n' 0 > z.txt
  git commit -qam "fix: widen a line"; git push -q origin evolve/reviewed; git switch -q main )
git -C "$tmp/work" rev-parse evolve/reviewed > "$tmp/pr-head-oid"
git -C "$tmp/origin.git" update-ref refs/pull/5/head "$(cat "$tmp/pr-head-oid")"
refuses "a head that adds a line over 100 characters" "over 100 characters: z.txt:1" run

# --- running from a mutable source ---------------------------------------------
# The checkout may serve the installed skill, so the mid-sequence branch switch
# can rewrite this very script on disk; everything after it must already be parsed.
# The copy keeps its installed layout so it resolves its sibling idd-plan scripts.
fresh; git -C "$tmp/work" switch -q evolve/reviewed
real_git="$(command -v git)"
mkdir -p "$tmp/skills/idd-evolve/scripts"; ln -sfn "$root/skills/idd-plan" "$tmp/skills/idd-plan"
copy="$tmp/skills/idd-evolve/scripts/copy.sh"
cp "$script" "$copy"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = switch ] && [ -n "\${REWRITE_TARGET:-}" ]; then yes 'exit 99' | head -4000 > "\$REWRITE_TARGET"; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
out="$(cd "$tmp/work" && REWRITE_TARGET="$copy" bash "$copy" 5 2>&1)" || {
  echo "the script failed once its own source was rewritten mid-run: $out" >&2; exit 1; }
case "$out" in "landed example/demo#5 as "*) ;; *) echo "a rewritten source did not report completion: $out" >&2; exit 1;; esac
rm -f "$tmp/bin/git"

echo "land-evolution tests passed"
