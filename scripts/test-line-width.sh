#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${LINE_WIDTH_SCRIPT:-$root/scripts/line-width.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

wide() { # $1 = character, $2 = count
  local out="" i
  for ((i = 0; i < $2; i++)); do out="$out$1"; done
  printf '%s' "$out"
}
passes() { # $1 = description, remaining = check arguments
  local desc="$1"; shift
  (cd "$tmp/repo" && bash "$script" check "$@" >/dev/null 2>&1) || {
    echo "line-width refused $desc" >&2; exit 1; }
}
refuses() { # $1 = description, $2 = required stderr fragment, remaining = check arguments
  local desc="$1" want="$2" err; shift 2
  if err="$(cd "$tmp/repo" && bash "$script" check "$@" 2>&1 >/dev/null)"; then
    echo "line-width accepted $desc" >&2; exit 1; fi
  case "$err" in
    *"$want"*) ;;
    *) echo "line-width refused $desc for the wrong reason: $err" >&2; exit 1;;
  esac
}
commit() { git -C "$tmp/repo" add -A; git -C "$tmp/repo" commit -qm "$1"; }

git init -q -b main "$tmp/repo"
# A legacy long line is debt the change does not own.
{ echo short; wide x 150; echo; } > "$tmp/repo/legacy.md"
commit "chore: seed"
base="$(git -C "$tmp/repo" rev-parse HEAD)"

echo "a short line" >> "$tmp/repo/legacy.md"; commit "docs: add a short line"
passes "a change that adds only short lines beside legacy debt" "$base"

{ wide y 100; echo; } > "$tmp/repo/limit.txt"; commit "test: add a line at the limit"
passes "a line of exactly 100 characters" "$base"

# Characters, not bytes: 100 two-byte characters fit, 101 do not.
wide é 100 > "$tmp/repo/accent.md"; echo >> "$tmp/repo/accent.md"; commit "docs: add accented text"
passes "100 multibyte characters" "$base"

mkdir "$tmp/repo/src"; wide z 101 > "$tmp/repo/src/deep.sh"
commit "feat: add a wide script line"
refuses "an added 101-character line" "over 100 characters: src/deep.sh:1" "$base"
refuses "an added line in every tracked text file, code included" "Formatter-owned" "$base"
git -C "$tmp/repo" rm -q src/deep.sh; commit "fix: drop the wide line"
passes "a line removed again before landing" "$base"

{ wide é 101; echo; } > "$tmp/repo/accent.md"; commit "docs: widen accented text"
refuses "101 multibyte characters" "accent.md:1" "$base"
git -C "$tmp/repo" checkout -q HEAD~1 -- accent.md; commit "docs: narrow accented text"

# Line numbers come from the new side of each hunk, and content that looks like a header
# is still content.
printf 'one\ntwo\n' > "$tmp/repo/notes.md"; commit "docs: add notes"
second="$(git -C "$tmp/repo" rev-parse HEAD)"
printf 'one\n++ b/looks-like-a-header %s\ntwo\n' "$(wide h 90)" > "$tmp/repo/notes.md"
commit "docs: add header-like"
refuses "a long line that starts like a diff header" "over 100 characters: notes.md:2" "$second"
git -C "$tmp/repo" checkout -q "$second" -- notes.md; commit "docs: restore notes"

# A formatter-owned path takes its tool's width; continuation lines extend the list.
mkdir -p "$tmp/repo/pkg" "$tmp/repo/tests/fixtures"
wide p 120 > "$tmp/repo/pkg/app.py"; wide j 130 > "$tmp/repo/package-lock.json"
wide f 140 > "$tmp/repo/tests/fixtures/recorded.txt"
rules="$tmp/repo/CLAUDE.md"
printf '# rules\n\nFormatter-owned: `*.py` `package-lock.json`\n  `tests/fixtures/`\n' > "$rules"
commit "build: add formatted and generated files"
passes "paths listed on the Formatter-owned line" "$base"
printf '# rules\n\nFormatter-owned: `*.py`\n' > "$rules"; commit "docs: narrow owned paths"
refuses "a generated file no longer listed" "package-lock.json:1" "$base"
printf '# rules\n\nFormatter-owned: `*.py` `package-lock.json` `tests/fixtures/`\n' > "$rules"
commit "docs: restore owned paths"
passes "a declaration read from the checked revision" "$base"

# A pure rename moves lines without adding them; a binary file has no lines.
git -C "$tmp/repo" mv legacy.md moved.md; commit "refactor: rename legacy"
printf '\000%s' "$(wide b 200)" > "$tmp/repo/blob.bin"; commit "chore: add a binary"
passes "a rename of a long-lined file and a binary file" "$base"

# The index mode checks exactly what a commit would record.
tip="$(git -C "$tmp/repo" rev-parse HEAD)"
wide i 101 > "$tmp/repo/staged.md"; git -C "$tmp/repo" add staged.md
refuses "a wide staged line" "staged.md:1" "$tip" --cached
git -C "$tmp/repo" rm -q --cached staged.md; rm "$tmp/repo/staged.md"
passes "an index with nothing wide" "$tip" --cached

# --root reads every tracked line, legacy included.
refuses "legacy debt under --root" "moved.md:2" --root
refuses "an unknown mode" "usage:" --root --cached

echo "line width gate valid"
