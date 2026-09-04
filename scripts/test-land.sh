#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
land_script="${LAND_SCRIPT:-$root/scripts/land.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
git init --bare "$tmp/origin.git" -q
git init "$tmp/work" -q
cd "$tmp/work"
git config user.email test@example.com; git config user.name Test
echo base > file; git add file; git commit -qm base; git branch -M main
git remote add origin "$tmp/origin.git"; git push -qu origin main
git checkout -qb issue/3-test; echo change >> file; git commit -qam change; git push -qu origin issue/3-test
printf OPEN > "$tmp/pr-state"; printf OPEN > "$tmp/issue-state"
printf 'Delivery-Type: feat\n' > "$tmp/pr-body"
printf 'Test the landing subject' > "$tmp/issue-title"
: > "$tmp/merge-subject"
: > "$tmp/merge-count"

cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${LAND_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then
  [[ "$*" == *nameWithOwner* ]] && echo maximalfocus/test || echo main
elif [ "$1 $2" = "pr view" ]; then
  key="${*: -1}"
  case "$key" in
    .state) cat "$root/pr-state";;
    .headRefName) echo issue/3-test;;
    .baseRefName) echo main;;
    .isCrossRepository|.isDraft) echo false;;
    '.reviewDecision // ""') echo APPROVED;;
    .mergeable) echo MERGEABLE;;
    .mergeCommit.oid) git rev-parse origin/main;;
    '.body // ""') cat "$root/pr-body";;
    *) echo '{}';;
  esac
elif [ "$1 $2" = "pr checks" ]; then exit 0
elif [ "$1 $2" = "pr merge" ]; then
  subject=""
  while [ "$#" -gt 0 ]; do
    [ "$1" = "--subject" ] && { subject="$2"; shift; }
    shift
  done
  if [ -n "${LAND_TEST_WRONG_SUBJECT:-}" ]; then
    printf '%s' "$LAND_TEST_WRONG_SUBJECT" > "$root/merge-subject"
  else
    printf '%s' "$subject" > "$root/merge-subject"
  fi
  printf 'x' >> "$root/merge-count"
  git push -q origin issue/3-test:main; echo MERGED > "$root/pr-state"
elif [ "$1 $2" = "issue view" ]; then
  key="${*: -1}"
  case "$key" in
    .title) cat "$root/issue-title";;
    *) cat "$root/issue-state";;
  esac
elif [ "$1 $2" = "issue close" ]; then echo CLOSED > "$root/issue-state"
elif [ "$1" = api ]; then
  key="${*: -1}"
  case "$key" in
    .commit.message) cat "$root/merge-subject";;
    *) echo 1;;
  esac
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"


fresh() { # rebuild the work/origin pair and reset every recorded state file
  cd "$tmp"
  rm -rf "$tmp/work" "$tmp/origin.git"
  git init --bare "$tmp/origin.git" -q
  git init "$tmp/work" -q
  cd "$tmp/work"
  git config user.email test@example.com; git config user.name Test
  [ -f "$tmp/held-conventions" ] && cp "$tmp/held-conventions" CLAUDE.md
  echo base > file; git add file; [ -f CLAUDE.md ] && git add CLAUDE.md
  git commit -qm base; git branch -M main
  git remote add origin "$tmp/origin.git"; git push -qu origin main 2>/dev/null
  git checkout -qb issue/3-test; echo change >> file; git commit -qam change
  git push -qu origin issue/3-test 2>/dev/null
  printf OPEN > "$tmp/pr-state"; printf OPEN > "$tmp/issue-state"
  printf 'Delivery-Type: feat\n' > "$tmp/pr-body"
  printf 'Test the landing subject' > "$tmp/issue-title"
  : > "$tmp/merge-subject"; : > "$tmp/merge-count"
}

run() { PATH="$tmp/bin:$PATH" LAND_TEST_ROOT="$tmp" bash "$land_script" maximalfocus/test 3 13 >/dev/null; }
merges() { printf '%s' "$(wc -c < "$tmp/merge-count" | tr -d ' ')"; }
unchanged() { [ "$(cat "$tmp/pr-state")" = OPEN ] && [ "$(cat "$tmp/issue-state")" = OPEN ]; }
refuses() { # $1 = description, $2 = required stderr fragment
  local err
  err="$(PATH="$tmp/bin:$PATH" LAND_TEST_ROOT="$tmp" bash "$land_script" maximalfocus/test 3 13 2>&1 >/dev/null)" && {
    echo "idd-land accepted $1" >&2; exit 1; }
  case "$err" in
    *"$2"*) ;;
    *) echo "idd-land rejected $1 for the wrong reason: $err" >&2; exit 1;;
  esac
  unchanged || { echo "idd-land mutated GitHub while rejecting $1" >&2; exit 1; }
}

# Fail before the remote merge when the eventual ff-only default-branch refresh is impossible.
git branch -f main issue/3-test
refuses "a divergent local default branch" "cannot fast-forward"
git branch -f main origin/main

# --- delivery type: fail closed before any mutation -------------------------
printf 'No field here at all.\n' > "$tmp/pr-body"
refuses "a PR with no Delivery-Type field" "declares no 'Delivery-Type"

printf 'Delivery-Type: feat\nDelivery-Type: fix\n' > "$tmp/pr-body"
refuses "a PR declaring Delivery-Type twice" "declares Delivery-Type 2 times"

printf 'Delivery-Type: Feat\n' > "$tmp/pr-body"
refuses "a Delivery-Type that is not a lowercase token" "is not a lowercase type token"

# A declared repository vocabulary is binding.
printf '# conventions\n\n  Types: `feat` `fix` `docs`\n' > CLAUDE.md
git add CLAUDE.md; git commit -qm conventions
printf 'Delivery-Type: chore\n' > "$tmp/pr-body"
refuses "a Delivery-Type outside the repository's declared vocabulary" "is not one this repository allows"

# The 72-character authored budget is a stop, never a truncation.
printf 'Delivery-Type: feat\n' > "$tmp/pr-body"
printf 'Compose a landing subject that is deliberately far too long to fit inside the budget' > "$tmp/issue-title"
refuses "an authored subject over the 72-character budget" "over the 72 budget"
printf 'Test the landing subject' > "$tmp/issue-title"

# A repository that declares no vocabulary is not constrained to one.
mv CLAUDE.md "$tmp/held-conventions"
git rm -q --cached CLAUDE.md; git commit -qm "drop conventions"
printf 'Delivery-Type: chore\n' > "$tmp/pr-body"
PATH="$tmp/bin:$PATH" LAND_TEST_ROOT="$tmp" bash "$land_script" maximalfocus/test 3 13 >/dev/null \
  || { echo "idd-land rejected a well-formed type in a repository declaring none" >&2; exit 1; }
[ "$(cat "$tmp/merge-subject")" = "chore: test the landing subject (#13)" ] || {
  echo "unexpected subject: $(cat "$tmp/merge-subject")" >&2; exit 1; }

# The postcondition is real: if the provider records a subject other than the
# composed one, landing must say so rather than accept it.
cp CLAUDE.md "$tmp/held-conventions" 2>/dev/null || true
fresh
if err="$(PATH="$tmp/bin:$PATH" LAND_TEST_ROOT="$tmp" LAND_TEST_WRONG_SUBJECT="something else entirely" \
    bash "$land_script" maximalfocus/test 3 13 2>&1 >/dev/null)"; then
  echo "idd-land accepted a landed subject it did not compose" >&2; exit 1
fi
case "$err" in
  *"Landed subject is not the composed one"*) ;;
  *) echo "wrong reason for a mismatched landed subject: $err" >&2; exit 1;;
esac

# --- the ordinary case, then an idempotent resume ---------------------------
fresh
run
[ "$(git branch --show-current)" = main ]
! git show-ref --verify --quiet refs/heads/issue/3-test
! git ls-remote --exit-code --heads origin issue/3-test >/dev/null 2>&1
[ "$(cat "$tmp/pr-state")" = MERGED ] && [ "$(cat "$tmp/issue-state")" = CLOSED ]
[ "$(cat "$tmp/merge-subject")" = "feat: test the landing subject (#13)" ] || {
  echo "landed subject was $(cat "$tmp/merge-subject")" >&2; exit 1; }
after_first="$(merges)"
[ "$after_first" = 1 ] || { echo "expected exactly one merge, saw $after_first" >&2; exit 1; }

# Resuming an already-landed PR must not merge again, and must not re-check a
# subject it did not write — even when the issue title has since changed.
printf 'A completely different title written after landing' > "$tmp/issue-title"
run
[ "$(merges)" = "$after_first" ] || { echo "resume merged a second time" >&2; exit 1; }

# --- landing from a mutable source ------------------------------------------
# When the installed skill resolves into the repository being landed, the
# mid-sequence `git checkout <default>` rewrites the running script on disk.
# Bash reads a script incrementally, so everything after that checkout must
# already be parsed; a tail read from the rewritten file is a real failure.
fresh
real_git="$(command -v git)"
bundled="$land_script"
case "$(head -5 "$land_script")" in
  *'exec bash "$root/skills/idd-land/scripts/land.sh"'*)
    bundled="$(cd "$(dirname "$land_script")/.." && pwd)/skills/idd-land/scripts/land.sh";;
esac
cp "$bundled" "$tmp/land-copy.sh"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = checkout ] && [ -n "\${LAND_TEST_REWRITE:-}" ]; then
  yes 'exit 99' | head -4000 > "\$LAND_TEST_REWRITE"
fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
if out="$(PATH="$tmp/bin:$PATH" LAND_TEST_ROOT="$tmp" LAND_TEST_REWRITE="$tmp/land-copy.sh" \
    bash "$tmp/land-copy.sh" maximalfocus/test 3 13 2>&1)"; then
  case "$out" in
    *LANDED*) ;;
    *) echo "landing from a rewritten source did not report completion: $out" >&2; exit 1;;
  esac
else
  echo "idd-land failed once its own source was rewritten mid-landing: $out" >&2; exit 1
fi
rm "$tmp/bin/git"

echo "idd-land lifecycle valid"
