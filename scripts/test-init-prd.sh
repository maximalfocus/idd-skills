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
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MOCK_CREATED="$tmp/created" MOCK_REMOTE="$tmp/remote.git"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
output="$(bash "$init_prd_script" "$tmp/demo-prd" example/demo-prd)"
grep -q '^repository=https://github.com/example/demo-prd$' <<<"$output"
[ "$(git -C "$tmp/demo-prd" ls-files | tr '\n' ' ')" = "PRD.md PROGRESS.md " ]
[ "$(git --git-dir="$tmp/remote.git" rev-parse main)" = "$(git -C "$tmp/demo-prd" rev-parse HEAD)" ]
echo "IDD PRD bootstrap valid"
