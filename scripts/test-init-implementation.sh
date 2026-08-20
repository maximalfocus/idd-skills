#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
init_implementation_script="${INIT_IMPLEMENTATION_SCRIPT:-$root/scripts/init-implementation.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/widget-prd"
git -C "$tmp/widget-prd" init -q -b main
: >"$tmp/widget-prd/PRD.md"; : >"$tmp/widget-prd/PROGRESS.md"
git -C "$tmp/widget-prd" add PRD.md PROGRESS.md
git -C "$tmp/widget-prd" -c user.name=Test -c user.email=test@example.com commit -qm base
git -C "$tmp/widget-prd" remote add origin https://github.com/example/widget-prd.git
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
    mkdir "$MOCK_PARENT/widget"; git -C "$MOCK_PARENT/widget" init -q -b main
    printf '# Widget\n' >"$MOCK_PARENT/widget/README.md"
    git -C "$MOCK_PARENT/widget" add README.md
    git -C "$MOCK_PARENT/widget" -c user.name=Test -c user.email=test@example.com commit -qm initial
    git -C "$MOCK_PARENT/widget" remote add origin https://github.com/example/widget.git
    touch "$MOCK_CREATED" ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" MOCK_CREATED="$tmp/created" MOCK_PARENT="$tmp"
output="$(bash "$init_implementation_script" "$tmp/widget-prd")"
grep -q "^implementation=$tmp/widget$" <<<"$output"
grep -q '^repository=https://github.com/example/widget$' <<<"$output"
grep -q '^visibility=PRIVATE$' <<<"$output"
grep -q '^created=true$' <<<"$output"
[ "$(git -C "$tmp/widget" ls-files)" = README.md ]
echo "IDD implementation bootstrap valid"
