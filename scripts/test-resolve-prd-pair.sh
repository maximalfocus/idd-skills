#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/widget"
git -C "$tmp/widget" init -q
git -C "$tmp/widget" remote add origin git@github.com:example/widget.git

set +e
bash "$root/scripts/resolve-prd-pair.sh" "$tmp/widget" >"$tmp/out"
rc=$?
set -e
[ "$rc" -eq 3 ] && [ ! -s "$tmp/out" ] || { echo "missing PRD was not treated as unconfigured" >&2; exit 1; }

mkdir "$tmp/widget-prd"
git -C "$tmp/widget-prd" init -q
git -C "$tmp/widget-prd" remote add origin https://github.com/example/widget-prd.git
: > "$tmp/widget-prd/PRD.md"; : > "$tmp/widget-prd/PROGRESS.md"

expected="implementation=$tmp/widget
prd=$tmp/widget-prd"
[ "$(bash "$root/scripts/resolve-prd-pair.sh" "$tmp/widget")" = "$expected" ]
[ "$(bash "$root/scripts/resolve-prd-pair.sh" "$tmp/widget-prd")" = "$expected" ]

git -C "$tmp/widget" config user.email test@example.com
git -C "$tmp/widget" config user.name Test
: > "$tmp/widget/file"; git -C "$tmp/widget" add file; git -C "$tmp/widget" commit -qm base
git -C "$tmp/widget" worktree add -qb issue/1 "$tmp/widget-worktree"
worktree_expected="implementation=$tmp/widget-worktree
prd=$tmp/widget-prd"
[ "$(bash "$root/scripts/resolve-prd-pair.sh" "$tmp/widget-worktree")" = "$worktree_expected" ]

git -C "$tmp/widget-prd" remote set-url origin https://github.com/other/widget-prd.git
if bash "$root/scripts/resolve-prd-pair.sh" "$tmp/widget" >/dev/null 2>&1; then
  echo "mismatched PRD origin was accepted" >&2; exit 1
fi

echo "IDD PRD-pair resolution valid"
