#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="$root/skills/idd/SKILL.md"

[ -f "$skill" ] || { echo "Missing: $skill" >&2; exit 1; }
[ "$(head -1 "$skill")" = "---" ] || { echo "Missing YAML frontmatter" >&2; exit 1; }
grep -q '^name: idd$' "$skill" || { echo "Invalid or missing skill name" >&2; exit 1; }
grep -q '^description: ' "$skill" || { echo "Missing description" >&2; exit 1; }
grep -q '^## GATE ' "$skill" || { echo "Missing delivery gate" >&2; exit 1; }
lines=$(wc -l < "$skill" | tr -d ' ')
[ "$lines" -le 160 ] || { echo "SKILL.md exceeds 160 lines ($lines)" >&2; exit 1; }

git -C "$root" diff --check
echo "idd skill valid ($lines lines)"
