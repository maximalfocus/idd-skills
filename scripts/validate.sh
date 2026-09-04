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
validate_skill idd-auto 120
validate_skill idd-evolve 80
validate_skill idd-publish 120
validate_skill idd-acceptance 120
[ -f "$root/CONSTITUTION.md" ] || { echo "Missing CONSTITUTION.md" >&2; exit 1; }
grep -q 'explicit target or current checkout' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must resolve the target methodology checkout" >&2; exit 1; }

install_home="$(mktemp -d)"
trap 'rm -rf "$install_home"' EXIT
HOME="$install_home" CODEX_HOME="$install_home/.codex" bash "$root/scripts/install.sh" >/dev/null
for name in idd-plan idd-issue idd idd-land idd-auto idd-evolve idd-publish idd-acceptance; do
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

bash -n "$root/scripts/install.sh"
bash -n "$root/scripts/test-install.sh"
[ -x "$root/scripts/install.sh" ] || { echo "install.sh must be executable" >&2; exit 1; }
[ -x "$root/scripts/test-install.sh" ] || { echo "test-install.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-install.sh"

grep -q 'explicit request' "$root/skills/idd-issue/SKILL.md" || { echo "idd-issue must require explicit creation authority" >&2; exit 1; }
grep -q 'open and closed issues' "$root/skills/idd-issue/SKILL.md" || { echo "idd-issue must search open and closed issues" >&2; exit 1; }
grep -q 'gh issue view' "$root/skills/idd-issue/SKILL.md" || { echo "idd-issue must verify the created issue" >&2; exit 1; }
grep -q 'post-plan' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must cover planning evidence" >&2; exit 1; }
grep -q 'post-create' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must cover issue-creation evidence" >&2; exit 1; }
grep -Fq '`$idd-land #N`' "$root/skills/idd/SKILL.md" || { echo "idd must emit Codex next actions with dollar syntax" >&2; exit 1; }
grep -q 'at most one next issue' "$root/CONSTITUTION.md" || { echo "constitution must bound idd-plan output" >&2; exit 1; }
grep -q 'product-only clarification' "$root/CONSTITUTION.md" || { echo "constitution must bound greenfield questions" >&2; exit 1; }
grep -q 'draft-only opt-out' "$root/CONSTITUTION.md" || { echo "constitution must define greenfield publication default" >&2; exit 1; }
grep -q 'unless the user explicitly asks for draft-only output' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan must publish greenfield PRDs by default" >&2; exit 1; }
grep -q '^## Reconstruct mode' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan must reconstruct a PRD from implemented source" >&2; exit 1; }
grep -q 'never invent issue numbers' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconstruct must not invent lifecycle evidence" >&2; exit 1; }
grep -q 'one verified implementation baseline' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconstruct must collapse implemented scope to one baseline" >&2; exit 1; }
grep -q 'never turn each past commit' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconstruct must not create historical delivery rows" >&2; exit 1; }
grep -q 'reconstruct' "$root/CONSTITUTION.md" || { echo "constitution must authorize the reconstruct bootstrap" >&2; exit 1; }
grep -q 'Edit only `PROGRESS.md`' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconcile must be tracker-only" >&2; exit 1; }
grep -q 'implementation control panel' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan must keep progress implementation-focused" >&2; exit 1; }
grep -q 'implementation control panel rather than a commit or delivery log' "$root/CONSTITUTION.md" || { echo "constitution must keep progress out of history tracking" >&2; exit 1; }
grep -q 'requires no separate user invocation' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must automatically reconcile progress" >&2; exit 1; }
grep -q 'Delivery-Type' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must document the declared delivery type" >&2; exit 1; }
grep -q 'Delivery-Type' "$root/skills/idd/SKILL.md" || { echo "idd must declare the delivery type landing requires" >&2; exit 1; }
grep -q -- '--subject' "$root/skills/idd-land/scripts/land.sh" || { echo "idd-land must compose the squash subject, not accept the provider default" >&2; exit 1; }
grep -q 'explicit `/idd-auto` invocation' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must require explicit authority" >&2; exit 1; }
grep -q 'one active issue at a time' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must serialize issue delivery" >&2; exit 1; }
grep -q 'scripts/resolve-prd-pair.sh' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must require an exact PRD pair" >&2; exit 1; }
grep -q 'scripts/init-implementation.sh' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must bootstrap a uniquely missing implementation sibling" >&2; exit 1; }
grep -q 'Do not auto-apply `--accept-residuals`' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must fail closed on residuals" >&2; exit 1; }
grep -q 'never invoked' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must not invoke publication" >&2; exit 1; }
grep -q 'idd-acceptance' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must require final integrated acceptance" >&2; exit 1; }
grep -q 'Do not invoke `/idd-evolve` for a project defect' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must separate project defects from methodology evolution" >&2; exit 1; }
grep -q 'real product boundary' "$root/skills/idd-acceptance/SKILL.md" || { echo "idd-acceptance must use a real product boundary" >&2; exit 1; }
grep -q 'explicit `/idd-publish` invocation' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must require explicit visibility authority" >&2; exit 1; }
grep -q 'defaulting to MIT' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must default unspecified licenses to MIT" >&2; exit 1; }
grep -q 'anonymous' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must verify public/private readback" >&2; exit 1; }
grep -q 'companion PRD owner/name' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must denylist the private companion identity" >&2; exit 1; }
grep -q 'scripts/scan-exposure.sh' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must run the scripted exposure scan" >&2; exit 1; }
grep -q 'bare stem, never anchored to a file extension' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must match denylist terms by bare stem" >&2; exit 1; }
grep -q 'A commit-message match is always that blocker' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must treat a commit-message match as unpurgeable" >&2; exit 1; }
grep -q 'permanent provider surfaces' "$root/skills/idd/SKILL.md" || { echo "idd must keep private companion material out of permanent provider text" >&2; exit 1; }
grep -q 'matched by bare stem' "$root/CONSTITUTION.md" || { echo "constitution must bound denylist term form" >&2; exit 1; }
grep -q 'advance its lifecycle status only when' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must preserve tracker lifecycle semantics" >&2; exit 1; }

bash -n "$root/scripts/resolve-prd-pair.sh"
bash -n "$root/scripts/test-resolve-prd-pair.sh"
[ -x "$root/scripts/resolve-prd-pair.sh" ] || { echo "resolve-prd-pair.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-resolve-prd-pair.sh"

bash -n "$root/scripts/init-prd.sh"
bash -n "$root/scripts/test-init-prd.sh"
[ -x "$root/scripts/init-prd.sh" ] || { echo "init-prd.sh must be executable" >&2; exit 1; }
[ -x "$root/scripts/test-init-prd.sh" ] || { echo "test-init-prd.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-init-prd.sh"

bash -n "$root/scripts/init-implementation.sh"
bash -n "$root/scripts/test-init-implementation.sh"
[ -x "$root/scripts/init-implementation.sh" ] || { echo "init-implementation.sh must be executable" >&2; exit 1; }
[ -x "$root/scripts/test-init-implementation.sh" ] || { echo "test-init-implementation.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-init-implementation.sh"

bash -n "$root/skills/idd-acceptance/scripts/static-gate.sh"
[ -x "$root/skills/idd-acceptance/scripts/static-gate.sh" ] || { echo "acceptance static gate must be executable" >&2; exit 1; }

bash -n "$root/scripts/scan-exposure.sh"
bash -n "$root/scripts/test-scan-exposure.sh"
[ -x "$root/scripts/scan-exposure.sh" ] || { echo "scan-exposure.sh must be executable" >&2; exit 1; }
[ -x "$root/scripts/test-scan-exposure.sh" ] || { echo "test-scan-exposure.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-scan-exposure.sh"

bash -n "$root/scripts/land.sh"
[ -x "$root/scripts/land.sh" ] || { echo "land.sh must be executable" >&2; exit 1; }
grep -q 'scripts/land.sh' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must invoke land.sh" >&2; exit 1; }
grep -q 'explicit invocation' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must require explicit invocation" >&2; exit 1; }
grep -q -- '--accept-residuals' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must gate residual acceptance" >&2; exit 1; }
grep -q '^land_main "\$@"; exit \$?$' "$root/skills/idd-land/scripts/land.sh" || { echo "land.sh must run as one parsed function" >&2; exit 1; }
bash "$root/scripts/test-land.sh"

for name in tracker-gate manifest; do
  bash -n "$root/scripts/$name.sh"
  bash -n "$root/scripts/test-$name.sh"
  [ -x "$root/scripts/$name.sh" ] || { echo "$name.sh must be executable" >&2; exit 1; }
  [ -x "$root/scripts/test-$name.sh" ] || { echo "test-$name.sh must be executable" >&2; exit 1; }
  bash "$root/scripts/test-$name.sh"
done
grep -q 'scripts/tracker-gate.sh PROGRESS.md' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconcile must run the tracker gate" >&2; exit 1; }
grep -q 'tracker-gate.sh' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must run the tracker gate before reconciliation" >&2; exit 1; }
grep -q 'PRD text stale' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconcile must report stale requirement prose" >&2; exit 1; }
grep -q 'landed, PRD text stale' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must name the stale-prose outcome" >&2; exit 1; }
grep -q 'None declared' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan must write an explicit empty manifest" >&2; exit 1; }
grep -q 'manifest.sh candidates' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconstruct must propose manifest candidates mechanically" >&2; exit 1; }
grep -q 'manifest.sh drift' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan reconcile must report manifest drift" >&2; exit 1; }
grep -q 'manifest.sh verify' "$root/skills/idd-acceptance/SKILL.md" || { echo "idd-acceptance must verify manifest rows" >&2; exit 1; }
grep -q 'never executes goldens' "$root/CONSTITUTION.md" || { echo "constitution must keep acceptance from executing goldens" >&2; exit 1; }
grep -q 'only artifacts its manifest names' "$root/CONSTITUTION.md" || { echo "constitution must bound what a contract repository tracks" >&2; exit 1; }

bash -n "$root/scripts/test-portable-install.sh"
[ -x "$root/scripts/test-portable-install.sh" ] || { echo "test-portable-install.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-portable-install.sh"

git -C "$root" diff --check
echo "idd skills valid for Claude Code, Codex, Pi, and OpenCode"
