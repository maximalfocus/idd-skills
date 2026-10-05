#!/usr/bin/env bash
set -euo pipefail
# Parse Git output as bytes; the width counter decodes UTF-8 independently of the locale.
export LC_ALL=C

# Refuse any line a change adds to a tracked text file beyond 100 characters, the one
# width every IDD-managed repository shares (idd-plan/references/conventions.md). A path
# listed on the repository's `Formatter-owned:` line in AGENTS.md or CLAUDE.md is left to
# the tool that lays it out: a language formatter at its configured width, or a generator,
# package manager, or recorder. A Markdown table row is one line that cannot be rewrapped,
# so its cells answer to their own budgets (the tracker gate's) instead of this width.
#
#   line-width.sh check BASE            lines the change in hand adds since its merge base:
#                                       the working tree when it is dirty, else HEAD
#   line-width.sh check BASE REV        lines REV adds since its merge base
#   line-width.sh check BASE --cached   lines the index adds to BASE
#   line-width.sh check --root [REV]    every line of REV's tracked text files
#
# A valid UTF-8 sequence counts once and every byte outside one counts once, so the count
# never depends on the locale the gate runs in. Only added lines count, so a change never
# inherits the debt of lines it leaves alone, and a pure rename adds none.
usage() { echo "usage: line-width.sh check BASE|--root [REV|--cached]" >&2; exit 64; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] && [ "$1" = check ] || usage
base="$2"; rev="${3:-HEAD}"; given_rev="${3:-}"
limit=100
[ "$base:$rev" != --root:--cached ] || usage
top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Not in a git repository" >&2; exit 1; }
cd "$top"
# Resolve both revisions here, so a diff option passed as one is refused, not misread.
if [ "$rev" != --cached ]; then
  rev="$(git rev-parse --verify --end-of-options "$rev^{commit}")"
fi
if [ "$base" != --root ]; then
  base="$(git rev-parse --verify --end-of-options "$base^{commit}")"
fi

# git diff shows a symlink's link text and a worktree file through its filters and
# working-tree encoding. Read the same content for the measured side; -w stores the
# object in the scratch store, so the repository's own objects stay untouched.
scratch="$(mktemp -d)"; trap 'rm -rf "$scratch"' EXIT
scratch_objects="$scratch/objects"; mkdir -p "$scratch_objects"
real_objects="$(git rev-parse --path-format=absolute --git-path objects)"
worktree_side() { # $1 = path; the content git diff shows for the worktree side
  if [ -L "$1" ]; then readlink -- "$1" 2>/dev/null || true
  elif [ -r "$1" ]; then
    local oid
    oid="$(GIT_OBJECT_DIRECTORY="$scratch_objects" \
      GIT_ALTERNATE_OBJECT_DIRECTORIES="$real_objects" \
      git hash-object -w --path="$1" --stdin < "$1" 2>/dev/null || true)"
    [ -n "$oid" ] || return 0
    GIT_OBJECT_DIRECTORY="$scratch_objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$real_objects" \
    git cat-file blob "$oid" 2>/dev/null || true
  fi
}

declared() { # $1 = conventions file as the checked side holds it; prints its owned paths
  local text
  if [ "$rev" = --cached ]; then text="$(git show ":$1" 2>/dev/null || true)"
  elif [ -n "$measured" ]; then text="$(worktree_side "$1")"
  else text="$(git show "$rev:$1" 2>/dev/null || true)"; fi
  printf '%s\n' "$text" | awk '
    /^[[:space:]]*Formatter-owned:/ {
      on = 1; sub(/^[[:space:]]*Formatter-owned:/, ""); print; next }
    on && /^[[:space:]]*(`[^`]+`[[:space:]]*)+$/ { print; next }
    { on = 0 }' | awk -F '`' '{ for (i = 2; i < NF; i += 2) print $i }'
}

empty_tree="$(git hash-object -t tree /dev/null)"
measured=
if [ "$rev" = --cached ]; then
  range=(--cached "$base")
elif [ "$base" = --root ]; then
  range=("$empty_tree" "$rev")
else
  merge_base="$(git merge-base "$base" "$rev")" || {
    echo "No merge base between $base and $rev" >&2; exit 1; }
  range=("$merge_base" "$rev")
  # Asked about the change in hand, measure the change in hand. With no REV the old default
  # was HEAD, so running this while still working passed on the previous commit and reported
  # a width no one had checked; the same content failed once committed.
  if [ -z "$given_rev" ] && [ -n "$(git diff --name-only "$rev" -- . 2>/dev/null)" ]; then
    range=("$merge_base"); measured=" (working tree)"
  fi
fi

# Owned paths are Git pathspec patterns: keep each whole, spaces included, and refuse the
# magic that would turn one exemption into a hole across the whole gate.
excludes=()
for conventions in AGENTS.md CLAUDE.md; do
  while IFS= read -r owned; do
    [ -n "$owned" ] || continue
    case "$owned" in
      :\(*\)*)
        magic="${owned%%)*}"; magic="${magic:2}"
        case ",$magic," in
          *,exclude,*|*,\!,*|*,^,*)
            echo "Formatter pathspec must be positive: $owned" >&2; exit 1;;
        esac
        excludes+=(":(exclude,${owned:2}");;
      :/*) excludes+=(":(exclude,top)${owned:2}");;
      :*) echo "Unsupported formatter pathspec: $owned" >&2; exit 1;;
      *) excludes+=(":(exclude)$owned");;
    esac
  done < <(declared "$conventions")
done

# The content side of the measured range, and its index or tree entry.
right_side() { # $1 = path
  if [ "$rev" = --cached ]; then git cat-file blob ":$1"
  elif [ -n "$measured" ]; then worktree_side "$1"
  else git cat-file blob "$rev:$1"; fi
}
entry_of() { # $1 = path
  if [ "$rev" = --cached ] || [ -n "$measured" ]; then
    git ls-files --stage -- ":(literal)$1"
  else
    git ls-tree "$rev" -- ":(literal)$1"
  fi
}

# Classify changed blobs by their contents, not .gitattributes' diff presentation, so an
# attribute cannot turn plain text into a width exemption and a real binary stays out.
# NUL-delimited names preserve whitespace, tabs, newlines, and pathspec metacharacters.
git diff --no-ext-diff --no-textconv --find-renames --name-only -z --diff-filter=ACMRT \
  "${range[@]}" -- . ${excludes[@]+"${excludes[@]}"} > "$scratch/paths"
while IFS= read -r -d '' path; do
  [[ "$(entry_of "$path")" != 160000* ]] || continue # a gitlink has no blob to read
  right_side "$path" > "$scratch/blob"
  # Git treats a NUL in the first 8000 bytes as binary; use the same content rule.
  head -c 8000 "$scratch/blob" > "$scratch/prefix"
  if [ "$(LC_ALL=C tr -d '\000' < "$scratch/prefix" | wc -c)" \
    -ne "$(wc -c < "$scratch/prefix")" ]; then
    excludes+=(":(exclude,literal)$path")
  fi
done < "$scratch/paths"

# Headers only precede a file's first hunk, and every hunk line carries a +, -, or \
# prefix, so added content can never be read as a header. Git quotes unusual paths, so a
# diagnostic stays printable. A later NUL may still truncate an awk record: map it to one
# byte that cannot join a UTF-8 sequence, and count either byte as one character.
wide="$(git -c core.quotePath=true diff --no-color --no-ext-diff --no-textconv -U0 \
  --text --inter-hunk-context=0 --output-indicator-new=+ --output-indicator-old=- \
  --output-indicator-context=' ' \
  --find-renames --src-prefix=a/ --dst-prefix=b/ "${range[@]}" \
  -- . ${excludes[@]+"${excludes[@]}"} |
  tr '\000' '\001' |
  awk -v limit="$limit" '
    BEGIN { for (i = 1; i < 256; i++) byte[sprintf("%c", i)] = i }
    function cont(b) { return b >= 128 && b <= 191 }
    function chars(s, i, n, a, b, c, d, step) {
      # Accept only complete Unicode scalar encodings: no overlongs or surrogates.
      # Every other byte counts once, including truncated prefixes.
      n = 0
      for (i = 1; i <= length(s); i += step) {
        a = byte[substr(s, i, 1)]; b = byte[substr(s, i + 1, 1)]
        c = byte[substr(s, i + 2, 1)]; d = byte[substr(s, i + 3, 1)]
        step = 1
        if (a >= 194 && a <= 223 && cont(b)) step = 2
        else if (cont(c) && ((a == 224 && b >= 160 && b <= 191) ||
          (a >= 225 && a <= 236 && cont(b)) || (a == 237 && b >= 128 && b <= 159) ||
          (a >= 238 && a <= 239 && cont(b)))) step = 3
        else if (cont(c) && cont(d) && ((a == 240 && b >= 144 && b <= 191) ||
          (a >= 241 && a <= 243 && cont(b)) || (a == 244 && b >= 128 && b <= 143))) step = 4
        if (++n > limit) return n
      }
      return n
    }
    function markdown(p) { # a table row cannot be rewrapped, so its cells are exempt
      if (substr(p, length(p), 1) == "\"") p = substr(p, 1, length(p) - 1)
      return p ~ /\.(md|markdown)$/
    }
    /^diff --git / { hunk = 0; next }
    hunk && /^\+/ {
      if (!(markdown(path) && substr($0, 2) ~ /^[ \t]*\|/) && chars(substr($0, 2)) > limit)
        printf "%s:%d\n", path, line
      line++; next
    }
    !hunk && /^\+\+\+ / {
      path = substr($0, 5); sub(/^b\//, "", path); sub(/^"b\//, "\"", path); next
    }
    /^@@ / { hunk = 1; split($3, start, ","); line = substr(start[1], 2) + 0; next }')"
if [ -n "$wide" ]; then
  printf '%s\n' "$wide" | sed "s/^/over $limit characters: /" >&2
  echo "Rewrap each line to $limit characters, or list its path on the repository's" \
    "Formatter-owned: line only when a formatter, generator, package manager, or recorder" \
    "lays it out (idd-plan/references/conventions.md)" >&2
  exit 1
fi
echo "PASS: no added line over $limit characters$measured"
