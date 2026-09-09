#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/skills/idd-evolve/scripts/propose.sh"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$tmp/bin"
export PROPOSE_TEST_ROOT="$tmp"
export PATH="$tmp/bin:$PATH"

cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${PROPOSE_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then
  [[ "$*" == *nameWithOwner* ]] && echo example/demo || echo main
elif [ "$1 $2" = "pr create" ]; then
  shift 2; : > "$root/pr-args"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --title) printf 'title=%s\n' "$2" >> "$root/pr-args"; shift;;
      --body-file) cp "$2" "$root/pr-body"; shift;;
      --base|--head|--repo) printf '%s=%s\n' "${1#--}" "$2" >> "$root/pr-args"; shift;;
    esac
    shift
  done
  echo https://github.com/example/demo/pull/5
elif [ "$1 $2" = "pr view" ]; then echo OPEN
else echo "unexpected gh: $*" >&2; exit 2
fi
FAKE
chmod +x "$tmp/bin/gh"

fresh() { # a bare origin with one commit on main and a clean clone of it
  rm -rf "$tmp/origin.git" "$tmp/work" "$tmp/other" "$tmp"/pr-*
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/work" 2>/dev/null
  git -C "$tmp/work" switch -q -c main 2>/dev/null || true
  printf 'a\n' > "$tmp/work/a.txt"; printf 'b\n' > "$tmp/work/b.txt"; printf 'c\n' > "$tmp/work/c.txt"
  git -C "$tmp/work" add -A; git -C "$tmp/work" commit -qm "chore: init"; git -C "$tmp/work" push -q -u origin main
  printf 'a2\n' > "$tmp/work/a.txt"; printf 'b2\n' > "$tmp/work/b.txt"; printf 'c2\n' > "$tmp/work/c.txt"
}
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "propose accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "propose rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
}
printf 'evolve: route kept evolutions through pull requests\n\nEvidence: direct pushes hid changes from review.\n\nKept: one branch per evolution.\n' > "$tmp/msg"

# --- the happy path -------------------------------------------------------------
fresh
url="$(cd "$tmp/work" && bash "$script" reviewed-evolutions "$tmp/msg" a.txt b.txt)"
[ "$url" = https://github.com/example/demo/pull/5 ] || { echo "unexpected output: $url" >&2; exit 1; }
[ "$(git -C "$tmp/work" symbolic-ref --short HEAD)" = main ] || { echo "checkout must return to main" >&2; exit 1; }
[ "$(git -C "$tmp/work" rev-parse main)" = "$(git -C "$tmp/work" rev-parse origin/main)" ] || { echo "main must be untouched" >&2; exit 1; }
[ "$(cat "$tmp/work/a.txt")" = a ] || { echo "committed paths must revert to main in the checkout" >&2; exit 1; }
[ "$(cat "$tmp/work/c.txt")" = c2 ] || { echo "unrelated changes must stay in the working tree" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" rev-list --count main..evolve/reviewed-evolutions)" = 1 ] || { echo "origin must hold one commit on the evolve branch" >&2; exit 1; }
files="$(git -C "$tmp/origin.git" diff --name-only main evolve/reviewed-evolutions | sort | tr '\n' ' ')"
[ "$files" = "a.txt b.txt " ] || { echo "commit must contain exactly the named paths: $files" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" log -1 --format=%B evolve/reviewed-evolutions)" = "$(cat "$tmp/msg")" ] || { echo "commit message must be the file verbatim" >&2; exit 1; }
grep -qx 'title=evolve: route kept evolutions through pull requests' "$tmp/pr-args" || { echo "PR title must be the subject" >&2; exit 1; }
grep -qx 'base=main' "$tmp/pr-args" && grep -qx 'head=evolve/reviewed-evolutions' "$tmp/pr-args" && grep -qx 'repo=example/demo' "$tmp/pr-args" || { echo "PR must target main from the evolve branch: $(cat "$tmp/pr-args")" >&2; exit 1; }
[ "$(cat "$tmp/pr-body")" = "$(printf 'Evidence: direct pushes hid changes from review.\n\nKept: one branch per evolution.')" ] || { echo "PR body must be the commit body" >&2; exit 1; }

# --- a subject-only message opens a PR with an empty body ----------------------
fresh; printf 'fix: tighten the slug check\n' > "$tmp/msg1"
(cd "$tmp/work" && bash "$script" slug-check "$tmp/msg1" a.txt >/dev/null)
[ ! -s "$tmp/pr-body" ] || { echo "a subject-only message must open an empty PR body" >&2; exit 1; }

# --- message discipline (N-4) ----------------------------------------------------
fresh
printf 'Evolve: capitalised\n' > "$tmp/bad"; refuses "a capitalised subject" "listed type (N-4)" bash -c "cd '$tmp/work' && bash '$script' x '$tmp/bad' a.txt"
printf 'feature: unlisted type\n' > "$tmp/bad"; refuses "an unlisted type" "listed type (N-4)" bash -c "cd '$tmp/work' && bash '$script' x '$tmp/bad' a.txt"
printf 'evolve(two words): bad scope\n' > "$tmp/bad"; refuses "a scope with a space" "listed type (N-4)" bash -c "cd '$tmp/work' && bash '$script' x '$tmp/bad' a.txt"
printf 'evolve: %s\n' "$(printf 'x%.0s' $(seq 1 70))" > "$tmp/bad"; refuses "a 78-character subject" "exceeds 72" bash -c "cd '$tmp/work' && bash '$script' x '$tmp/bad' a.txt"
printf 'evolve: no blank line\nbody\n' > "$tmp/bad"; refuses "a body glued to the subject" "one blank line" bash -c "cd '$tmp/work' && bash '$script' x '$tmp/bad' a.txt"
: > "$tmp/bad"; refuses "an empty message" "missing or empty" bash -c "cd '$tmp/work' && bash '$script' x '$tmp/bad' a.txt"
refuses "a bad slug" "lowercase kebab-case" bash -c "cd '$tmp/work' && bash '$script' Bad_Slug '$tmp/msg' a.txt"
refuses "too few arguments" "usage:" bash -c "cd '$tmp/work' && bash '$script' slug '$tmp/msg'"

# --- checkout state --------------------------------------------------------------
fresh; refuses "an unchanged path" "No change under c.txt" bash -c "cd '$tmp/work' && git checkout -q c.txt && bash '$script' slug '$tmp/msg' a.txt c.txt"
fresh; refuses "pre-staged changes" "Index already has staged changes" bash -c "cd '$tmp/work' && git add c.txt && bash '$script' slug '$tmp/msg' a.txt"
fresh; refuses "a non-default branch" "Propose from main" bash -c "cd '$tmp/work' && git switch -q -c side && bash '$script' slug '$tmp/msg' a.txt"
fresh; git -C "$tmp/work" commit -qam "chore: local only"; printf 'a3\n' > "$tmp/work/a.txt"
refuses "a local main ahead of origin" "commits origin lacks" bash -c "cd '$tmp/work' && bash '$script' slug '$tmp/msg' a.txt"
fresh; git clone -q "$tmp/origin.git" "$tmp/other" 2>/dev/null; printf 'd\n' > "$tmp/other/d.txt"; git -C "$tmp/other" add d.txt; git -C "$tmp/other" commit -qm "chore: upstream"; git -C "$tmp/other" push -q origin main
refuses "a local main behind origin" "behind origin" bash -c "cd '$tmp/work' && bash '$script' slug '$tmp/msg' a.txt"
fresh; git -C "$tmp/work" branch evolve/slug; refuses "an existing local branch" "already exists locally" bash -c "cd '$tmp/work' && bash '$script' slug '$tmp/msg' a.txt"
fresh; git -C "$tmp/work" push -q origin main:refs/heads/evolve/slug; refuses "an existing origin branch" "already exists on origin" bash -c "cd '$tmp/work' && bash '$script' slug '$tmp/msg' a.txt"
# Every refusal above left main untouched and nothing pushed.
[ "$(git -C "$tmp/work" symbolic-ref --short HEAD)" = main ] || { echo "a refusal must leave the checkout on main" >&2; exit 1; }
[ "$(git -C "$tmp/origin.git" for-each-ref --format='%(refname:short)' refs/heads | sort | tr '\n' ' ')" = "evolve/slug main " ] || { echo "a refusal must push nothing" >&2; exit 1; }

# --- running from a mutable source ---------------------------------------------
# The checkout may serve the installed skill, so the mid-sequence branch switch
# can rewrite this very script on disk; everything after it must already be parsed.
fresh
real_git="$(command -v git)"
cp "$script" "$tmp/copy.sh"
cat > "$tmp/bin/git" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = switch ] && [ -n "\${REWRITE_TARGET:-}" ]; then yes 'exit 99' | head -4000 > "\$REWRITE_TARGET"; fi
exec "$real_git" "\$@"
FAKE
chmod +x "$tmp/bin/git"
out="$(cd "$tmp/work" && REWRITE_TARGET="$tmp/copy.sh" bash "$tmp/copy.sh" rewritten "$tmp/msg" a.txt 2>&1)" || { echo "the script failed once its own source was rewritten mid-run: $out" >&2; exit 1; }
case "$out" in *"pull/5") ;; *) echo "a rewritten source did not report completion: $out" >&2; exit 1;; esac
rm -f "$tmp/bin/git"

echo "propose tests passed"
