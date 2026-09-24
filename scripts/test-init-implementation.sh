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
default() { cat "$MOCK_DEFAULT" 2>/dev/null || echo main; }
case "$1 $2" in
  "pr list") ;;
  "auth status") exit 0 ;;
  "repo view")
    if [ -f "$MOCK_CREATED" ]; then
      if [[ "$*" == *"--json"* ]]; then
        printf 'example/widget\tPRIVATE\thttps://github.com/example/widget\t%s\n' "$(default)"; fi
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
  "api --method")
    body="$(cat)"
    if [[ "$body" == *default_branch* ]]; then echo dev > "$MOCK_DEFAULT"
    else touch "$MOCK_PROTECTED"; fi ;;
  "api repos/example/widget/branches/"*)
    git --git-dir="$MOCK_REMOTE" rev-parse -q --verify "refs/heads/${2##*/}" >/dev/null || {
      echo "gh: Branch not found (HTTP 404)" >&2; exit 1; } ;;
  "api repos/example/widget")
    if [[ "$*" == *.visibility* ]]; then echo private
    elif [[ "$*" == *.default_branch* ]]; then default
    elif [ -f "$MOCK_PROTECTED" ] && [ "$(default)" = dev ]; then
      echo "true true false true PR_TITLE PR_BODY"
    elif [ -f "$MOCK_PROTECTED" ]; then echo "true false false true PR_TITLE PR_BODY"
    else echo "true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES"; fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MOCK_CREATED="$tmp/created" MOCK_PARENT="$tmp"
export MOCK_REMOTE="$tmp/remotes/widget.git" MOCK_PROTECTED="$tmp/protected"
export MOCK_DEFAULT="$tmp/default"
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
grep -q '^integration=dev$' <<<"$output" || {
  echo "a new implementation repository must integrate on dev" >&2; exit 1; }
[ "$(git -C "$tmp/widget" branch --show-current)" = dev ] || {
  echo "the bootstrap checkout must be on dev" >&2; exit 1; }
[ "$(git --git-dir="$tmp/remotes/widget.git" rev-parse dev)" = "$pushed" ] || {
  echo "dev must start at the initial commit" >&2; exit 1; }

# --single-branch records the opt-out, so later phases never integrate on dev.
rm -rf "$tmp/widget" "$tmp/created" "$tmp/protected" "$tmp/default" "$tmp/remotes/widget.git"
git init -q --bare "$tmp/remotes/widget.git"
output="$(bash "$init_implementation_script" --single-branch "$tmp/widget-prd" 2>/dev/null)"
grep -q '^integration=main$' <<<"$output" || { echo "--single-branch must keep main" >&2; exit 1; }
[ "$(git -C "$tmp/widget" show HEAD:AGENTS.md)" = "Integration-branch: main" ] || {
  echo "--single-branch must record the opt-out" >&2; exit 1; }
! git --git-dir="$tmp/remotes/widget.git" rev-parse -q --verify dev >/dev/null || {
  echo "--single-branch must not create dev" >&2; exit 1; }
[ -f "$tmp/protected" ] || { echo "a single-branch bootstrap must still protect main" >&2; exit 1; }
echo "IDD implementation bootstrap valid"
