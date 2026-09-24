#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init_prd_script="${INIT_PRD_SCRIPT:-$root/scripts/init-prd.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/demo-prd"; : >"$tmp/demo-prd/PRD.md"; : >"$tmp/demo-prd/PROGRESS.md"
git init -q --bare "$tmp/remote.git"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view")
    if [[ "$*" == *"--json"* ]]; then printf 'example/demo-prd\tPRIVATE\thttps://github.com/example/demo-prd\n'; exit 0; fi
    [ -f "$MOCK_CREATED" ] ;;
  "repo create")
    touch "$MOCK_CREATED"
    while [ "$#" -gt 0 ]; do case "$1" in --source) source="$2"; shift 2;; *) shift;; esac; done
    git -C "$source" remote add origin "$MOCK_REMOTE"
    git -C "$source" push -q -u origin main ;;
  "api --method") cat >/dev/null; touch "$MOCK_PROTECTED" ;;
  "api repos/example/demo-prd")
    if [[ "$*" == *.visibility* ]]; then echo private
    elif [[ "$*" == *.default_branch* ]]; then echo main
    elif [ -f "$MOCK_PROTECTED" ]; then echo "true false false true PR_TITLE PR_BODY"
    else echo "true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES"; fi ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MOCK_CREATED="$tmp/created" MOCK_REMOTE="$tmp/remote.git"
export MOCK_PROTECTED="$tmp/protected"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
output="$(bash "$init_prd_script" "$tmp/demo-prd" example/demo-prd 2>/dev/null)"
grep -q '^repository=https://github.com/example/demo-prd$' <<<"$output"
[ -f "$tmp/protected" ] || { echo "Bootstrap must protect the PRD default branch" >&2; exit 1; }
# The one direct push a repository gets carries no line over the shared width.
mkdir "$tmp/wide-prd"; printf '%0101d\n' 0 >"$tmp/wide-prd/PRD.md"; : >"$tmp/wide-prd/PROGRESS.md"
if err="$(bash "$init_prd_script" "$tmp/wide-prd" example/wide-prd 2>&1)"; then
  echo "Bootstrap must refuse a line over 100 characters" >&2; exit 1
fi
[[ "$err" == *"over 100 characters: PRD.md:1"* ]] || {
  echo "wrong wide-line refusal: $err" >&2; exit 1; }
[ "$(git -C "$tmp/demo-prd" ls-files | tr '\n' ' ')" = "PRD.md PROGRESS.md " ]
[ "$(git --git-dir="$tmp/remote.git" rev-parse main)" = "$(git -C "$tmp/demo-prd" rev-parse HEAD)" ]
# Simulate GitHub identity while every transport still targets the temporary bare repo.
real_git="$(command -v git)"
printf '#!/bin/bash\nif [[ "$*" == *"remote get-url origin"* ]]; then echo https://github.com/example/demo-prd.git; else exec %q "$@"; fi\n' "$real_git" > "$tmp/bin/git"
chmod +x "$tmp/bin/git"
bash "$init_prd_script" "$tmp/demo-prd" example/demo-prd >/dev/null 2>&1
before="$(git --git-dir="$tmp/remote.git" rev-parse main)"
printf 'later row\n' >> "$tmp/demo-prd/PROGRESS.md"
git -C "$tmp/demo-prd" commit -qam 'progress: later row'
if err="$(bash "$init_prd_script" "$tmp/demo-prd" example/demo-prd 2>&1)"; then
  echo "Bootstrap retry must not push a post-bootstrap commit" >&2; exit 1
fi
[[ "$err" == *"Bootstrap already published"* ]]
[ "$(git --git-dir="$tmp/remote.git" rev-parse main)" = "$before" ]
grep -qx 'later row' "$tmp/demo-prd/PROGRESS.md"
echo "IDD PRD bootstrap valid"
