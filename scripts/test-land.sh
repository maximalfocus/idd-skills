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
    *) echo '{}';;
  esac
elif [ "$1 $2" = "pr checks" ]; then exit 0
elif [ "$1 $2" = "pr merge" ]; then
  git push -q origin issue/3-test:main; echo MERGED > "$root/pr-state"
elif [ "$1 $2" = "issue view" ]; then cat "$root/issue-state"
elif [ "$1 $2" = "issue close" ]; then echo CLOSED > "$root/issue-state"
elif [ "$1" = api ]; then echo 1
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"

run() { PATH="$tmp/bin:$PATH" LAND_TEST_ROOT="$tmp" bash "$land_script" maximalfocus/test 3 13 >/dev/null; }

# Fail before the remote merge when the eventual ff-only default-branch refresh is impossible.
git branch -f main issue/3-test
if run 2>/dev/null; then
  echo "idd-land accepted a divergent local default branch" >&2; exit 1
fi
[ "$(cat "$tmp/pr-state")" = OPEN ] && [ "$(cat "$tmp/issue-state")" = OPEN ]
git branch -f main origin/main

run
[ "$(git branch --show-current)" = main ]
! git show-ref --verify --quiet refs/heads/issue/3-test
! git ls-remote --exit-code --heads origin issue/3-test >/dev/null 2>&1
[ "$(cat "$tmp/pr-state")" = MERGED ] && [ "$(cat "$tmp/issue-state")" = CLOSED ]
run # idempotent resume after merge/closure/cleanup
echo "idd-land lifecycle valid"
