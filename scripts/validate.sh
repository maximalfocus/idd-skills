#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

validate_skill() {
  local name="$1"
  local cap="$2"
  local skill="$root/skills/$name/SKILL.md"

  [ -f "$skill" ] || { echo "Missing: $skill" >&2; exit 1; }
  [ "$(head -1 "$skill")" = "---" ] || { echo "Missing YAML frontmatter: $name" >&2; exit 1; }
  grep -q "^name: $name$" "$skill" || { echo "Invalid skill name: $name" >&2; exit 1; }
  grep -q '^description: ' "$skill" || { echo "Missing description: $name" >&2; exit 1; }
  grep -q '^argument-hint: ' "$skill" || { echo "Missing argument hint: $name" >&2; exit 1; }
  grep -Eq '^## (GATE|.*[Gg]ate)' "$skill" || { echo "Missing quality gate: $name" >&2; exit 1; }
  local lines
  lines=$(wc -l < "$skill" | tr -d ' ')
  [ "$lines" -le "$cap" ] || { echo "$name exceeds $cap lines ($lines)" >&2; exit 1; }
  echo "$name valid ($lines/$cap lines)"
}

validate_skill idd 160
validate_skill idd-evolve 80
[ -f "$root/CONSTITUTION.md" ] || { echo "Missing CONSTITUTION.md" >&2; exit 1; }
grep -q '../../CONSTITUTION.md' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must read the constitution" >&2; exit 1; }
git -C "$root" diff --check
echo "idd skills valid"
