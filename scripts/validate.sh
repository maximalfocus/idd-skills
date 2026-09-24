#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

has_phrase() { # $1 = file, $2 = fixed phrase; matches across the 100-column line wrap
  tr -s '[:space:]' ' ' < "$1" | grep -Fq -- "$2"
}

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

validate_skill idd-plan 160
validate_skill idd-issue 70
validate_skill idd 60
validate_skill idd-implement 160
validate_skill idd-land 120
validate_skill idd-auto 120
validate_skill idd-evolve 80
validate_skill idd-publish 120
validate_skill idd-acceptance 120
validate_skill idd-promote 60
[ -f "$root/CONSTITUTION.md" ] || { echo "Missing CONSTITUTION.md" >&2; exit 1; }
conventions="$root/skills/idd-plan/references/conventions.md"
[ -f "$conventions" ] || { echo "Missing shared conventions: $conventions" >&2; exit 1; }
if LC_ALL=en_US.UTF-8 grep -nE '^.{101,}' "$root"/skills/*/SKILL.md "$root/CONSTITUTION.md" \
  "$root/CLAUDE.md" "$conventions"; then
  echo "every line of the skills, CONSTITUTION.md, CLAUDE.md, and the conventions" \
    "must be 100 characters or fewer" >&2
  exit 1
fi
shared='skills/idd-plan/references/conventions.md'
has_phrase "$root/CONSTITUTION.md" "$shared" || {
  echo "constitution must bind every managed repository to the shared conventions" >&2; exit 1; }
has_phrase "$root/CLAUDE.md" "$shared" || {
  echo "CLAUDE.md must take its conventions from the shared source" >&2; exit 1; }
for script in skills/idd-land/scripts/land.sh skills/idd-plan/scripts/progress-pr.sh \
  skills/idd-plan/scripts/init-prd.sh skills/idd-evolve/scripts/propose.sh \
  skills/idd-evolve/scripts/land-evolution.sh; do
  grep -q 'line-width.sh' "$root/$script" || {
    echo "$script must gate the shared line width" >&2; exit 1; }
done
grep -q 'protect-main.sh" verify' "$root/skills/idd-land/scripts/land.sh" || {
  echo "land.sh must verify default-branch protection" >&2; exit 1; }
for name in idd idd-implement idd-land idd-auto; do
  has_phrase "$root/skills/$name/SKILL.md" 'protect-main.sh ensure' || {
    echo "$name must start by ensuring and printing the branch strategy" >&2; exit 1; }
done
grep -q 'protect-main.sh" ensure' "$root/skills/idd-plan/scripts/init-implementation.sh" || {
  echo "init-implementation.sh must integrate a new implementation repository on dev" >&2; exit 1; }
grep -q -- '--merge --match-head-commit' "$root/skills/idd-promote/scripts/promote.sh" || {
  echo "promote.sh must promote with a merge commit bound to the reviewed head" >&2; exit 1; }
grep -q '^Integration-branch: main$' "$root/CLAUDE.md" || {
  echo "this methodology repository must opt out of the dev integration branch" >&2; exit 1; }
for script in init-prd init-implementation; do
  grep -q 'protect-main.sh" apply' "$root/skills/idd-plan/scripts/$script.sh" || {
    echo "$script.sh must protect the new default branch" >&2; exit 1; }
done
has_phrase "$root/skills/idd-evolve/SKILL.md" 'explicit target or current checkout' || { echo "idd-evolve must resolve the target methodology checkout" >&2; exit 1; }

install_home="$(mktemp -d)"
trap 'rm -rf "$install_home"' EXIT
HOME="$install_home" CODEX_HOME="$install_home/.codex" bash "$root/scripts/install.sh" >/dev/null
for name in idd idd-plan idd-issue idd-implement idd-land idd-auto idd-evolve idd-publish \
  idd-acceptance idd-promote; do
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

has_phrase "$root/skills/idd-issue/SKILL.md" 'explicit request' || { echo "idd-issue must require explicit creation authority" >&2; exit 1; }
has_phrase "$root/skills/idd-issue/SKILL.md" 'open and closed issues' || { echo "idd-issue must search open and closed issues" >&2; exit 1; }
has_phrase "$root/skills/idd-issue/SKILL.md" 'gh issue view' || { echo "idd-issue must verify the created issue" >&2; exit 1; }
grep -q 'post-plan' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must cover planning evidence" >&2; exit 1; }
grep -q 'post-create' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must cover issue-creation evidence" >&2; exit 1; }
has_phrase "$root/skills/idd-implement/SKILL.md" '`$idd-land #N`' || { echo "idd-implement must emit Codex next actions with dollar syntax" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'at most one next issue' || { echo "constitution must bound idd-plan output" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'product-only clarification' || { echo "constitution must bound greenfield questions" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'draft-only opt-out' || { echo "constitution must define greenfield publication default" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'unless the user explicitly asks for draft-only output' || { echo "idd-plan must publish greenfield PRDs by default" >&2; exit 1; }
grep -q '^## Reconstruct mode' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan must reconstruct a PRD from implemented source" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'never invent issue numbers' || { echo "idd-plan reconstruct must not invent lifecycle evidence" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'one verified implementation baseline' || { echo "idd-plan reconstruct must collapse implemented scope to one baseline" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'never turn each past commit' || { echo "idd-plan reconstruct must not create historical delivery rows" >&2; exit 1; }
grep -q 'reconstruct' "$root/CONSTITUTION.md" || { echo "constitution must authorize the reconstruct bootstrap" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'Edit only `PROGRESS.md`' || { echo "idd-plan reconcile must be tracker-only" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'implementation control panel' || { echo "idd-plan must keep progress implementation-focused" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'implementation control panel rather than a commit or delivery log' || { echo "constitution must keep progress out of history tracking" >&2; exit 1; }
has_phrase "$root/skills/idd-land/SKILL.md" 'requires no separate user invocation' || { echo "idd-land must automatically reconcile progress" >&2; exit 1; }
grep -q 'Delivery-Type' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must document the declared delivery type" >&2; exit 1; }
grep -q 'Delivery-Type' "$root/skills/idd-implement/SKILL.md" || { echo "idd-implement must declare the delivery type landing requires" >&2; exit 1; }
has_phrase "$root/skills/idd/SKILL.md" 'Routing adds no authority' || { echo "idd router must add no authority" >&2; exit 1; }
has_phrase "$root/skills/idd/SKILL.md" 'reached only when the request names that action' || { echo "idd router must reach explicit-invocation phases only by name" >&2; exit 1; }
has_phrase "$root/skills/idd/SKILL.md" 'ask one question' || { echo "idd router must ask on ambiguity, never guess" >&2; exit 1; }
has_phrase "$root/skills/idd/SKILL.md" 'read-only `idd-plan` default mode' || { echo "idd router must bound planning inference to default mode" >&2; exit 1; }
has_phrase "$root/skills/idd/SKILL.md" 'Bootstrap, reconstruct, and reconcile require the request to name that mode' || { echo "idd router must require named planning mutations" >&2; exit 1; }
has_phrase "$root/skills/idd/SKILL.md" 'a missing or ambiguous pair is a question, never authority to bootstrap or reconstruct' || { echo "idd router must stop default-mode fallback to bootstrap" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'including where direct invocation is required' || { echo "constitution must define routed explicit invocation" >&2; exit 1; }
for name in idd-auto idd-land idd-publish; do
  has_phrase "$root/skills/$name/SKILL.md" 'directly or through `/idd`, per Constitution Article 5' || { echo "$name must honor routed explicit invocation" >&2; exit 1; }
done
has_phrase "$root/CONSTITUTION.md" 'adds no authority of its own' || { echo "constitution must deny the router any authority" >&2; exit 1; }
grep -q -- '--subject' "$root/skills/idd-land/scripts/land.sh" || { echo "idd-land must compose the squash subject, not accept the provider default" >&2; exit 1; }
has_phrase "$root/skills/idd-auto/SKILL.md" 'explicit `/idd-auto` invocation' || { echo "idd-auto must require explicit authority" >&2; exit 1; }
has_phrase "$root/skills/idd-auto/SKILL.md" 'one active issue at a time' || { echo "idd-auto must serialize issue delivery" >&2; exit 1; }
grep -q 'scripts/resolve-prd-pair.sh' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must require an exact PRD pair" >&2; exit 1; }
grep -q 'scripts/init-implementation.sh' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must bootstrap a uniquely missing implementation sibling" >&2; exit 1; }
has_phrase "$root/skills/idd-auto/SKILL.md" 'Do not auto-apply `--accept-residuals`' || { echo "idd-auto must fail closed on residuals" >&2; exit 1; }
has_phrase "$root/skills/idd-auto/SKILL.md" 'never invoked' || { echo "idd-auto must not invoke publication" >&2; exit 1; }
grep -q 'idd-acceptance' "$root/skills/idd-auto/SKILL.md" || { echo "idd-auto must require final integrated acceptance" >&2; exit 1; }
has_phrase "$root/skills/idd-auto/SKILL.md" 'Do not invoke `/idd-evolve` for a project defect' || { echo "idd-auto must separate project defects from methodology evolution" >&2; exit 1; }
has_phrase "$root/skills/idd-acceptance/SKILL.md" 'real product boundary' || { echo "idd-acceptance must use a real product boundary" >&2; exit 1; }
has_phrase "$root/skills/idd-publish/SKILL.md" 'explicit `/idd-publish` invocation' || { echo "idd-publish must require explicit visibility authority" >&2; exit 1; }
has_phrase "$root/skills/idd-publish/SKILL.md" 'defaulting to MIT' || { echo "idd-publish must default unspecified licenses to MIT" >&2; exit 1; }
grep -q 'anonymous' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must verify public/private readback" >&2; exit 1; }
has_phrase "$root/skills/idd-publish/SKILL.md" 'companion PRD owner/name' || { echo "idd-publish must denylist the private companion identity" >&2; exit 1; }
grep -q 'scripts/scan-exposure.sh' "$root/skills/idd-publish/SKILL.md" || { echo "idd-publish must run the scripted exposure scan" >&2; exit 1; }
has_phrase "$root/skills/idd-publish/SKILL.md" 'bare stem, never anchored to a file extension' || { echo "idd-publish must match denylist terms by bare stem" >&2; exit 1; }
has_phrase "$root/skills/idd-publish/SKILL.md" 'A commit-message match is always that blocker' || { echo "idd-publish must treat a commit-message match as unpurgeable" >&2; exit 1; }
has_phrase "$root/skills/idd-implement/SKILL.md" 'permanent provider surfaces' || { echo "idd-implement must keep private companion material out of permanent provider text" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'matched by bare stem' || { echo "constitution must bound denylist term form" >&2; exit 1; }
has_phrase "$root/skills/idd-publish/SKILL.md" 'advance its lifecycle status only when' || { echo "idd-publish must preserve tracker lifecycle semantics" >&2; exit 1; }

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
! grep -q "\brg\b" "$root/skills/idd-acceptance/scripts/static-gate.sh" || { echo "acceptance static gate must not depend on ripgrep" >&2; exit 1; }
bash -n "$root/scripts/test-static-gate.sh"
[ -x "$root/scripts/test-static-gate.sh" ] || { echo "test-static-gate.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-static-gate.sh"

bash -n "$root/scripts/scan-exposure.sh"
bash -n "$root/scripts/test-scan-exposure.sh"
[ -x "$root/scripts/scan-exposure.sh" ] || { echo "scan-exposure.sh must be executable" >&2; exit 1; }
[ -x "$root/scripts/test-scan-exposure.sh" ] || { echo "test-scan-exposure.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-scan-exposure.sh"

bash -n "$root/scripts/land.sh"
[ -x "$root/scripts/land.sh" ] || { echo "land.sh must be executable" >&2; exit 1; }
grep -q 'scripts/land.sh' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must invoke land.sh" >&2; exit 1; }
has_phrase "$root/skills/idd-land/SKILL.md" 'explicit invocation' || { echo "idd-land must require explicit invocation" >&2; exit 1; }
grep -q -- '--accept-residuals' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must gate residual acceptance" >&2; exit 1; }
grep -q '^land_main "\$@"; exit \$?$' "$root/skills/idd-land/scripts/land.sh" || { echo "land.sh must run as one parsed function" >&2; exit 1; }
bash "$root/scripts/test-land.sh"

for name in tracker-gate manifest prd-fold-gate prd-size-gate contract progress-pr protect-main \
  line-width propose land-evolution promote; do
  bash -n "$root/scripts/$name.sh"
  bash -n "$root/scripts/test-$name.sh"
  [ -x "$root/scripts/$name.sh" ] || { echo "$name.sh must be executable" >&2; exit 1; }
  [ -x "$root/scripts/test-$name.sh" ] || { echo "test-$name.sh must be executable" >&2; exit 1; }
  bash "$root/scripts/test-$name.sh"
done
has_phrase "$root/skills/idd-plan/SKILL.md" 'scripts/tracker-gate.sh PROGRESS.md' || { echo "idd-plan reconcile must run the tracker gate" >&2; exit 1; }
grep -q 'tracker-gate.sh' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must run the tracker gate before reconciliation" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'scripts/progress-pr.sh sync <contract-path>' || { echo "idd-plan reconcile must edit the synced progress batch" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'The batch merges only at a milestone' || { echo "idd-plan must merge progress batches only at a milestone" >&2; exit 1; }
has_phrase "$root/skills/idd-land/SKILL.md" 'progress-pr.sh sync' || { echo "idd-land must sync the PRD progress batch before reconciliation" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'changes only through a pull request' || { echo "constitution must route PRD default-branch changes through a pull request" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'PRD text stale' || { echo "idd-plan reconcile must report stale requirement prose" >&2; exit 1; }
has_phrase "$root/skills/idd-land/SKILL.md" 'landed, PRD text stale' || { echo "idd-land must name the stale-prose outcome" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'None declared' || { echo "idd-plan must write an explicit empty manifest" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'manifest.sh candidates' || { echo "idd-plan reconstruct must propose manifest candidates mechanically" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'manifest.sh drift' || { echo "idd-plan reconcile must report manifest drift" >&2; exit 1; }
has_phrase "$root/skills/idd-acceptance/SKILL.md" 'manifest.sh verify' || { echo "idd-acceptance must verify manifest rows" >&2; exit 1; }
grep -q 'prd-fold-gate.sh' "$root/skills/idd-acceptance/SKILL.md" || { echo "idd-acceptance must report unfolded validated slices" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'scripts/prd-fold-gate.sh PRD.md PROGRESS.md' || { echo "idd-plan reconcile must report unfolded validated slices" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'collapses to one row' || { echo "idd-plan must fold validated slices into requirements" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'keeps no section of its own' || { echo "constitution must keep validated slices out of the PRD body" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'scripts/prd-size-gate.sh PRD.md' || { echo "idd-plan must gate PRD size" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'PRD over budget' || { echo "idd-plan reconcile must report an over-budget contract" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" '--reconstruct --scope' || { echo "idd-plan reconstruct must accept a scope" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'PRD size gate' || { echo "constitution must name the PRD size gate" >&2; exit 1; }
grep -q 'folding' "$root/skills/idd-plan/SKILL.md" && has_phrase "$root/skills/idd-land/SKILL.md" 'folding the tracker' || { echo "a stopped tracker gate must name the folding reconcile as its repair" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'never executes goldens' || { echo "constitution must keep acceptance from executing goldens" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'only artifacts its manifest names' || { echo "constitution must bound what a contract repository tracks" >&2; exit 1; }
has_phrase "$root/skills/idd-plan/SKILL.md" 'scripts/contract.sh gate' || { echo "idd-plan must run the contract gate" >&2; exit 1; }
grep -q -- '--context' "$root/skills/idd-plan/SKILL.md" || { echo "idd-plan must select a context" >&2; exit 1; }
has_phrase "$root/skills/idd-implement/SKILL.md" 'contract.sh owner' || { echo "idd-implement must check touched files against the issue's context scope" >&2; exit 1; }
grep -q 'contract.sh' "$root/skills/idd-land/SKILL.md" || { echo "idd-land must gate the whole contract before reconciliation" >&2; exit 1; }
grep -q 'contexts/' "$root/CONSTITUTION.md" || { echo "constitution must admit context contracts" >&2; exit 1; }
has_phrase "$root/CONSTITUTION.md" 'Depends on' || { echo "constitution must bound cross-context dependencies" >&2; exit 1; }

has_phrase "$root/CONSTITUTION.md" 'only through a pull request' || { echo "constitution must route kept evolutions through a reviewed pull request" >&2; exit 1; }
has_phrase "$root/skills/idd-evolve/SKILL.md" 'scripts/protect-main.sh verify' || { echo "idd-evolve must verify the default branch is protected before editing" >&2; exit 1; }
grep -q 'scripts/propose.sh' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must publish through propose.sh" >&2; exit 1; }
grep -q 'scripts/land-evolution.sh' "$root/skills/idd-evolve/SKILL.md" || { echo "idd-evolve must land a reviewed PR only through land-evolution.sh" >&2; exit 1; }
has_phrase "$root/skills/idd-evolve/SKILL.md" 'explicit instruction' || { echo "idd-evolve landing must require the maintainer's explicit instruction" >&2; exit 1; }
grep -q -- '--subject' "$root/skills/idd-evolve/scripts/land-evolution.sh" || { echo "land-evolution.sh must compose the squash subject" >&2; exit 1; }
grep -q '^propose_main "\$@"; exit \$?$' "$root/skills/idd-evolve/scripts/propose.sh" || { echo "propose.sh must run as one parsed function" >&2; exit 1; }
grep -q '^land_evolution_main "\$@"; exit \$?$' "$root/skills/idd-evolve/scripts/land-evolution.sh" || { echo "land-evolution.sh must run as one parsed function" >&2; exit 1; }
! grep -Eq 'push (`)?main' "$root/skills/idd-evolve/SKILL.md" "$root/CONSTITUTION.md" "$root/CLAUDE.md" || { echo "no methodology text may push main directly" >&2; exit 1; }
grep -q 'evolve/<' "$root/CLAUDE.md" || { echo "CLAUDE.md must name the evolve branch convention" >&2; exit 1; }

bash -n "$root/scripts/test-portable-install.sh"
[ -x "$root/scripts/test-portable-install.sh" ] || { echo "test-portable-install.sh must be executable" >&2; exit 1; }
bash "$root/scripts/test-portable-install.sh"

git -C "$root" diff --check
echo "idd skills valid for Claude Code, Codex, Pi, and OpenCode"
