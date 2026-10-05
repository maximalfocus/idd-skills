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

# A Markdown table row cannot be rewrapped, so its cells answer to their own budgets; a
# pipe-led line outside Markdown, or prose beside the table, still answers to the width.
printf '| id | %s |\n  | %s |\n' "$(wide t 120)" "$(wide u 120)" > "$tmp/repo/table.md"
commit "docs: add a wide table"
passes "wide Markdown table rows, indented or not" "$base"
printf '  | %s\n' "$(wide q 120)" > "$tmp/repo/pipe.sh"; commit "feat: add a wide pipe line"
refuses "a wide pipe-led line outside Markdown" "over 100 characters: pipe.sh:1" "$base"
git -C "$tmp/repo" rm -q pipe.sh; commit "fix: drop the pipe line"
printf 'prose %s\n' "$(wide r 120)" >> "$tmp/repo/table.md"; commit "docs: add wide prose"
refuses "wide prose beside a table" "over 100 characters: table.md:3" "$base"
git -C "$tmp/repo" checkout -q HEAD~1 -- table.md; commit "docs: drop wide prose"

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

# Asked with no revision, the gate measures the change in hand. It used to measure HEAD, so a
# wide line still in the working tree passed and the same content failed once committed.
tip="$(git -C "$tmp/repo" rev-parse HEAD)"
wide w 130 > "$tmp/repo/inhand.md"
git -C "$tmp/repo" add inhand.md
refuses "a wide line still in the working tree" "inhand.md:1" "$tip"
passes "the same tree when HEAD is named explicitly" "$tip" HEAD
git -C "$tmp/repo" rm -q -f inhand.md
passes "a clean tree with nothing wide" "$tip"
wide w 140 >> "$tmp/repo/notes.md"
refuses "an unstaged wide line" "notes.md:3" "$tip"
git -C "$tmp/repo" checkout -q HEAD -- notes.md

# Working-tree content uses working-tree formatter declarations, including their removal.
printf '# rules\n' > "$rules"
wide p 140 >> "$tmp/repo/pkg/app.py"
refuses "a removed working-tree exemption" "pkg/app.py:1" "$tip"
passes "committed exemptions with an explicit revision" "$tip" HEAD
git -C "$tmp/repo" checkout -q HEAD -- CLAUDE.md pkg/app.py
printf 'Formatter-owned: `notes.md`\n' >> "$rules"
wide w 140 >> "$tmp/repo/notes.md"
passes "a new working-tree exemption" "$tip"
git -C "$tmp/repo" checkout -q HEAD -- CLAUDE.md notes.md

# --root reads every tracked line, legacy included.
refuses "legacy debt under --root" "moved.md:2" --root
refuses "an unknown mode" "usage:" --root --cached
refuses "a diff option passed as REV" "Needed a single revision" --root --name-only

# Declarations preserve spaces and Git magic; unrelated paths remain gated.
git -C "$tmp/repo" reset -q --hard HEAD
printf 'Formatter-owned: `generated files/`\n' > "$rules"
printf '%0101d\n' 0 > "$tmp/repo/generated"
commit "test: keep a spaced exemption narrow"
refuses "a space-split exemption" "generated:1" "$tip"
printf 'short\n' > "$tmp/repo/generated"
mkdir -p "$tmp/repo/generated files"
printf '%0101d\n' 0 > "$tmp/repo/generated files/output.txt"
commit "test: exempt the actual spaced path"
passes "the declared path with spaces" "$tip"
printf 'Formatter-owned: `:(glob)generated files/*.txt`\n' > "$rules"
commit "test: use pathspec magic"
passes "a glob magic declaration" "$tip"
printf 'Formatter-owned: `:(exclude)generated`\n' > "$rules"
git -C "$tmp/repo" add CLAUDE.md
refuses "a negative formatter pathspec" "must be positive" "$tip" --cached
git -C "$tmp/repo" restore --source=HEAD --staged --worktree CLAUDE.md

# Attributes cannot turn plain text into a width exemption.
printf 'generated -diff\n' > "$tmp/repo/.gitattributes"
printf '%0101d\n' 0 > "$tmp/repo/generated"
commit "test: disguise plain text as binary"
refuses "text with a binary diff attribute" "generated:1" "$tip"
refuses "text with a binary diff attribute in the index" "generated:1" "$tip" --cached
refuses "text with a binary diff attribute at bootstrap" "generated:1" --root
printf 'short\n' > "$tmp/repo/generated"
printf 'blob.bin diff\n' >> "$tmp/repo/.gitattributes"
commit "test: force a binary diff"
passes "actual binary content even with the diff attribute" "$tip"

# Unusual names cannot hide a line, and rename detection still ignores legacy debt.
printf '%0101d\n' 0 > "$tmp/repo/odd"$'\t\n'"name.txt"
commit "test: add a wide line under an unusual name"
refuses "a tab and newline in the filename" "over 100 characters:" "$tip"
git -C "$tmp/repo" rm -q -- "odd"$'\t\n'"name.txt"
commit "test: remove the unusual file"
passes "only exempt files and unchanged legacy debt" "$tip"
git -C "$tmp/repo" update-index --add --cacheinfo \
  "160000,1111111111111111111111111111111111111111,module"
passes "a submodule whose objects are absent locally" "$tip" --cached

# A symlink's width is its link text, the content git diff shows, not its target's; a
# binary target must not exempt it in the working-tree default.
symdir="$(wide s 110)"
mkdir -p "$tmp/repo/$symdir"
printf '\000\000' > "$tmp/repo/$symdir/blob"
symtip="$(git -C "$tmp/repo" rev-parse HEAD)"
ln -s "$symdir/blob" "$tmp/repo/symlink-new"
git -C "$tmp/repo" add -N symlink-new
refuses "a wide symlink in the working tree" "symlink-new:1" "$symtip"
git -C "$tmp/repo" reset -q -- symlink-new
rm -f "$tmp/repo/symlink-new"
rm -rf "$tmp/repo/$symdir"

# Batch encoding cases into one tree per width, keeping the locale/mode matrix small.
encoding="$tmp/encoding"
git init -q -b main "$encoding"
git -C "$encoding" commit -q --allow-empty -m 'chore: seed encoding tests'
encoding_base="$(git -C "$encoding" rev-parse HEAD)"
encoding_check() { # check both status and the complete path/line diagnostic list
  local output actual status=0
  output="$(cd "$encoding" && bash "$script" check "$@" 2>&1)" || status=$?
  actual="$(printf '%s\n' "$output" | sed -n 's/^over 100 characters: //p')"
  [ "$status" = "$((width - 100))" ] && [ "$actual" = "$expected" ] || {
    echo "encoding check failed ($test_locale, $*): $status / $output" >&2; exit 1; }
}
bad_path=$'caf\351.txt' # put it in the index: some filesystems reject non-UTF-8 names
for width in 100 101; do
  expected='"caf\351.txt":2'; line=1
  printf 'short\n' > "$encoding/encoded.txt"
  # Valid 2/3/4-byte scalars, overlong, surrogate, out-of-range, truncated, lone byte,
  # and an invalid prefix followed by a valid sequence. Each row states its character count.
  while read -r count octets; do
    { printf '%0*d' "$((width - count))" 0; printf '%b\n' "$octets"; } \
      >> "$encoding/encoded.txt"
    line=$((line + 1)); expected="$expected"$'\n'"encoded.txt:$line"
  done <<'OCTETS'
1 \302\200
1 \340\240\200
1 \364\217\277\277
2 \300\257
3 \355\240\200
4 \364\220\200\200
2 \342\202
1 \351
2 \342\303\251
OCTETS
  printf '# caf\351 short\n' > "$encoding/CLAUDE.md"
  # NUL at offset 8000 is outside the binary sample; it must still count once.
  { for ((i = 0; i < 4000; i++)); do printf 'a\n'; done
    printf '\000%0*d\n' "$((width - 1))" 0; } > "$encoding/late-nul.txt"
  expected="$expected"$'\n''late-nul.txt:4001'
  git -C "$encoding" add encoded.txt CLAUDE.md late-nul.txt
  blob="$(printf 'short\n%0*d\n' "$width" 0 | git -C "$encoding" hash-object -w --stdin)"
  git -C "$encoding" update-index --add --cacheinfo "100644,$blob,$bad_path"
  tree="$(git -C "$encoding" write-tree)"
  rev="$(git -C "$encoding" commit-tree "$tree" -p HEAD -m 'docs: add encoding fixtures')"
  [ "$width" != 100 ] || expected=""
  for test_locale in C en_SG.UTF-8; do
    LC_ALL="$test_locale" encoding_check "$encoding_base" --cached
    LC_ALL="$test_locale" encoding_check "$encoding_base" "$rev"
    LC_ALL="$test_locale" encoding_check --root "$rev"
  done
done

echo "line width gate valid"
