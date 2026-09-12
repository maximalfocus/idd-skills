#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init_implementation_script="${INIT_IMPLEMENTATION_SCRIPT:-$root/scripts/init-implementation.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
mkdir "$tmp/bin" "$tmp/widget-prd" "$tmp/remotes"
git -C "$tmp/widget-prd" init -q -b main
: >"$tmp/widget-prd/PRD.md"; : >"$tmp/widget-prd/PROGRESS.md"
git -C "$tmp/widget-prd" add PRD.md PROGRESS.md
git -C "$tmp/widget-prd" commit -qm base
git -C "$tmp/widget-prd" remote add origin https://github.com/example/widget-prd.git
git init -q --bare "$tmp/remotes/widget.git"
# The fake creates an empty repository, as gh does without --add-readme; pushes to the
# GitHub URL land in a local bare repository while the origin still reads as GitHub.
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view")
    if [ -f "$MOCK_CREATED" ]; then
      if [[ "$*" == *"--json"* ]]; then printf 'example/widget\tPRIVATE\thttps://github.com/example/widget\tmain\n'; fi
      exit 0
    fi
    exit 1 ;;
  "repo create")
    [[ "$*" != *--add-readme* ]] || { echo "the provider's initial commit is untyped" >&2; exit 1; }
    mkdir "$MOCK_PARENT/widget"; git -C "$MOCK_PARENT/widget" init -q
    git -C "$MOCK_PARENT/widget" remote add origin https://github.com/example/widget.git
    git -C "$MOCK_PARENT/widget" config \
      url."$MOCK_REMOTE".pushInsteadOf https://github.com/example/widget.git
    touch "$MOCK_CREATED" ;;
  "api --method") cat >/dev/null; touch "$MOCK_PROTECTED" ;;
  "api repos/example/widget")
    if [[ "$*" == *.visibility* ]]; then echo private
    elif [ -f "$MOCK_PROTECTED" ]; then echo "true false false true PR_TITLE PR_BODY"
    else echo "true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES"; fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MOCK_CREATED="$tmp/created" MOCK_PARENT="$tmp"
export MOCK_REMOTE="$tmp/remotes/widget.git" MOCK_PROTECTED="$tmp/protected"
output="$(bash "$init_implementation_script" "$tmp/widget-prd" 2>/dev/null)"
grep -q "^implementation=$tmp/widget$" <<<"$output"
grep -q '^repository=https://github.com/example/widget$' <<<"$output"
grep -q '^visibility=PRIVATE$' <<<"$output"
grep -q '^created=true$' <<<"$output"
[ "$(git -C "$tmp/widget" ls-files)" = README.md ]
subject="$(git -C "$tmp/widget" log -1 --format=%s)"
[ "$subject" = "docs: establish the implementation repository" ] || {
  echo "the initial commit must carry an N-4 subject: $subject" >&2; exit 1; }
pushed="$(git --git-dir="$tmp/remotes/widget.git" rev-parse main)"
[ "$pushed" = "$(git -C "$tmp/widget" rev-parse HEAD)" ] || {
  echo "the initial commit must be pushed to main" >&2; exit 1; }
[ -f "$tmp/protected" ] || {
  echo "bootstrap must protect the implementation default branch" >&2; exit 1; }
echo "IDD implementation bootstrap valid"
