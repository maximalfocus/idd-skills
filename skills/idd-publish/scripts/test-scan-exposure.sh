#!/usr/bin/env bash
# Regression tests for scan-exposure.sh.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scan-exposure.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

decode_hex() {
  local hex="$1" escaped=""
  while [ -n "$hex" ]; do
    escaped+="\\x${hex:0:2}"
    hex="${hex:2}"
  done
  printf '%b' "$escaped"
}

repo="$work/impl"
git init -q "$repo"
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name Tester

printf 'clean source\n' >"$repo/app.txt"
git -C "$repo" add app.txt
git -C "$repo" commit -q -m "feat: clean commit"

# A clean repository passes.
"$script" "$repo" "COMPANION-prd" >/dev/null || { echo "FAIL: clean repo must pass" >&2; exit 1; }

# The proven defect: a term supplied as a filename must still match the same name used
# without its extension, and the match must be found in a commit MESSAGE, not just a blob.
printf 'more source\n' >>"$repo/app.txt"
git -C "$repo" commit -qam "feat: vulnerable code (authorized by the METHODOLOGY §0 carve-out)"

if "$script" "$repo" "METHODOLOGY.md" >"$work/out" 2>"$work/err"; then
  echo "FAIL: extension-anchored term must still match a bare stem in a commit message" >&2
  exit 1
fi
grep -q '^commit	' "$work/out" || { echo "FAIL: hit must be reported as a commit-message hit" >&2; exit 1; }
grep -q 'UNPURGEABLE' "$work/err" || { echo "FAIL: commit-message hit must be flagged unpurgeable" >&2; exit 1; }

# Blob content is scanned too, and reported as a blob rather than a commit.
printf 'see maximalfocus/impl-prd for rationale\n' >"$repo/notes.md"
git -C "$repo" add notes.md
git -C "$repo" commit -q -m "docs: notes"
"$script" "$repo" "maximalfocus/impl-prd" >"$work/out2" 2>/dev/null && {
  echo "FAIL: blob match must block" >&2; exit 1; }
grep -q '^blob	notes.md	' "$work/out2" || { echo "FAIL: blob hit must name its path" >&2; exit 1; }

# A short abbreviation must not match inside an unrelated word.
repo2="$work/impl2"
git init -q "$repo2"
git -C "$repo2" config user.email t@example.invalid
git -C "$repo2" config user.name Tester
printf 'the delta between salta and volta\n' >"$repo2/a.txt"
git -C "$repo2" add a.txt
git -C "$repo2" commit -q -m "chore: unrelated words"
"$script" "$repo2" >/dev/null || { echo "FAIL: short mandatory abbreviation must respect word boundaries" >&2; exit 1; }

# A built-in secret pattern that starts with "-" must still be applied, not eaten by grep
# as an option, and must not emit a broken-pipe warning on content larger than a pipe buffer.
repo3="$work/impl3"
git init -q "$repo3"
git -C "$repo3" config user.email t@example.invalid
git -C "$repo3" config user.name Tester
{ decode_hex 2d2d2d2d2d424547494e205253412050524956415445204b45592d2d2d2d2d0a; head -c 200000 /dev/zero | tr '\0' 'x'; } >"$repo3/key.pem"
git -C "$repo3" add key.pem
git -C "$repo3" commit -q -m "chore: add key"
"$script" "$repo3" >"$work/out3" 2>"$work/err3" && { echo "FAIL: private key must block" >&2; exit 1; }
grep -q 'credential' "$work/out3" || { echo "FAIL: private key must be reported as a credential" >&2; exit 1; }
grep -qi 'broken pipe' "$work/err3" && { echo "FAIL: scan must not emit broken-pipe warnings" >&2; exit 1; }

# A mandatory minimum term is enforced without the caller restating it, including when
# the matching file exists only in an older commit and is absent from every ref tip.
repo4="$work/impl4"
git init -q "$repo4"
git -C "$repo4" config user.email t@example.invalid
git -C "$repo4" config user.name Tester
printf 'clean source\n' >"$repo4/app.txt"
git -C "$repo4" add app.txt
git -C "$repo4" commit -q -m "feat: clean source"
printf 'contact %s\n' "$(decode_hex 4c616e64205472616e73706f727420417574686f72697479)" >"$repo4/retired.txt"
git -C "$repo4" add retired.txt
git -C "$repo4" commit -q -m "docs: add retired reference"
git -C "$repo4" rm -q retired.txt
git -C "$repo4" commit -q -m "docs: remove retired reference"
test ! -e "$repo4/retired.txt" || { echo "FAIL: history-only fixture still exists at the ref tip" >&2; exit 1; }
"$script" "$repo4" >"$work/out4" 2>"$work/err4" && {
  echo "FAIL: mandatory history-only denylist term must block" >&2; exit 1; }
grep -q $'^blob\tretired.txt\tterm\t' "$work/out4" || {
  echo "FAIL: history-only blob hit must name its former path" >&2; exit 1; }

# The tracked scanner and test sources must remain clean under their own mandatory rules.
repo5="$work/impl5"
git init -q "$repo5"
git -C "$repo5" config user.email t@example.invalid
git -C "$repo5" config user.name Tester
cp "$script" "$repo5/scan-exposure.sh"
cp "${BASH_SOURCE[0]}" "$repo5/test-scan-exposure.sh"
git -C "$repo5" add scan-exposure.sh test-scan-exposure.sh
git -C "$repo5" commit -q -m "test: scanner components"
"$script" "$repo5" >/dev/null || { echo "FAIL: scanner components must self-scan cleanly" >&2; exit 1; }

echo "scan-exposure.sh tests passed"
