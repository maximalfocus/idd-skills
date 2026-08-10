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
  grep -q '^compatibility: ' "$skill" || { echo "Missing compatibility declaration: $name" >&2; exit 1; }
  grep -Eq '^## (GATE|.*[Gg]ate)' "$skill" || { echo "Missing quality gate: $name" >&2; exit 1; }
  local lines
  lines=$(wc -l < "$skill" | tr -d ' ')
  [ "$lines" -le "$cap" ] || { echo "$name exceeds $cap lines ($lines)" >&2; exit 1; }
  echo "$name valid ($lines/$cap lines)"
}

validate_skill idd-plan 90
validate_skill idd-issue 70
validate_skill idd 160
validate_skill idd-land 120
validate_skill idd-evolve 80
[ -f "$root/CONSTITUTION.md" ] || { echo "Missing CONSTITUTION.md" >&2; exit 1; }
grep -q '../../CONSTITUTION.md' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must read the constitution" >&2; exit 1; }

install_home="$(mktemp -d)"
trap 'rm -rf "$install_home"' EXIT
HOME="$install_home" CODEX_HOME="$install_home/.codex" bash "$root/scripts/install.sh" >/dev/null
for name in idd-plan idd-issue idd idd-land idd-evolve; do
  source_dir="$root/skills/$name"
  for link in \
    "$install_home/.claude/skills/$name" \
    "$install_home/.codex/skills/$name" \
    "$install_home/.agents/skills/$name"; do
    [ -L "$link" ] && [ "$(readlink "$link")" = "$source_dir" ] || {
      echo "Invalid install link: $link" >&2
      exit 1
    }
  done
done
# Pi and OpenCode both discover the shared .agents installation.
[ -L "$install_home/.agents/skills/idd" ] || { echo "Missing shared Pi/OpenCode install" >&2; exit 1; }

grep -q 'explicit request' "$root/skills/idd-issue/SKILL.md" || { echo "idd-issue must require explicit creation authority" >&2; exit 1; }
grep -q 'open and closed issues' "$root/skills/idd-issue/SKILL.md" || { echo "idd-issue must search open and closed issues" >&2; exit 1; }
grep -q 'gh issue view' "$root/skills/idd-issue/SKILL.md" || { echo "idd-issue must verify the created issue" >&2; exit 1; }
grep -q 'post-plan' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must cover planning evidence" >&2; exit 1; }
grep -q 'post-create' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must cover issue-creation evidence" >&2; exit 1; }
grep -Fq '`$idd-land #N`' "$root/skills/idd/SKILL.md" || { echo "idd must emit Codex next actions with dollar syntax" >&2; exit 1; }
grep -q 'at most one next issue' "$root/CONSTITUTION.md" || { echo "constitution must bound idd-plan output" >&2; exit 1; }
grep -q 'product-only clarification' "$root/CONSTITUTION.md" || { echo "constitution must bound greenfield questions" >&2; exit 1; }
grep -q 'Edit only `PROGRESS.md`' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconcile must be tracker-only" >&2; exit 1; }
grep -q 'requires no separate user invocation' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must automatically reconcile progress" >&2; exit 1; }

bash -n "$root/scripts/resolve-prd-pair.sh"
bash -n "$root/scripts/test-resolve-prd-pair.sh"
[ -x "$root/scripts/resolve-prd-pair.sh" ] || { echo "resolve-prd-pair.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-resolve-prd-pair.sh"

bash -n "$root/scripts/init-prd.sh"
bash -n "$root/scripts/test-init-prd.sh"
[ -x "$root/scripts/init-prd.sh" ] || { echo "init-prd.sh must be executable" >&2; exit 1; }
[ -x "$root/scripts/test-init-prd.sh" ] || { echo "test-init-prd.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-init-prd.sh"

bash -n "$root/scripts/land.sh"
[ -x "$root/scripts/land.sh" ] || { echo "land.sh must be executable" >&2; exit 1; }
grep -q 'scripts/land.sh' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must invoke land.sh" >&2; exit 1; }
grep -q 'explicit invocation' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must require explicit invocation" >&2; exit 1; }
grep -q -- '--accept-residuals' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must gate residual acceptance" >&2; exit 1; }
bash "$root/scripts/test-land.sh"

git -C "$root" diff --check
echo "idd skills valid for Claude Code, Codex, Pi, and OpenCode"
