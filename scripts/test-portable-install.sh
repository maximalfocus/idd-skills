#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

copy_suite() {
  local destination="$1"
  mkdir -p "$destination"
  cp -R "$root/skills/." "$destination/"
}

agents_root="$work/project/.agents/skills"
codex_root="$work/codex/skills"
copy_suite "$agents_root"
copy_suite "$codex_root"

required_skills=(idd-plan idd-issue idd idd-land idd-auto idd-evolve idd-publish idd-acceptance)
for install_root in "$agents_root" "$codex_root"; do
  for name in "${required_skills[@]}"; do
    skill="$install_root/$name/SKILL.md"
    [ -f "$skill" ] || { echo "Missing copied skill: $skill" >&2; exit 1; }
    [ ! -L "$install_root/$name" ] || { echo "Copy install must not be a symlink: $name" >&2; exit 1; }

    frontmatter="$(awk 'NR == 1 && $0 == "---" { inside=1; next } inside && $0 == "---" { exit } inside { print }' "$skill")"
    while IFS= read -r key; do
      case "$key" in
        name|description|license|compatibility|metadata|allowed-tools) ;;
        *) echo "Unsupported Agent Skills frontmatter field in $name: $key" >&2; exit 1 ;;
      esac
    done < <(printf '%s\n' "$frontmatter" | sed -nE 's/^([a-z][a-z0-9-]*):.*/\1/p')
    grep -q "^name: $name$" "$skill" || { echo "Copied skill name mismatch: $name" >&2; exit 1; }
  done
done

for path in \
  idd-plan/scripts/resolve-prd-pair.sh \
  idd-plan/scripts/init-prd.sh \
  idd-plan/scripts/init-implementation.sh \
  idd-plan/scripts/tracker-gate.sh \
  idd-plan/scripts/manifest.sh \
  idd-plan/scripts/prd-fold-gate.sh \
  idd-land/scripts/land.sh \
  idd-publish/scripts/scan-exposure.sh \
  idd-publish/scripts/test-scan-exposure.sh; do
  [ -x "$agents_root/$path" ] || { echo "Missing executable installed resource: $path" >&2; exit 1; }
  bash -n "$agents_root/$path"
done

if grep -rEn '(\.\./\.\./CONSTITUTION\.md|idd-skills/scripts/|physical source repository)' "$agents_root"; then
  echo "Installed workflow still escapes to repository-root resources" >&2
  exit 1
fi

grep -q 'sibling `idd-plan`' "$agents_root/idd-land/SKILL.md" || {
  echo "idd-land must resolve its installed idd-plan dependency" >&2; exit 1; }
grep -q 'sibling `idd-plan`' "$agents_root/idd-acceptance/SKILL.md" || {
  echo "idd-acceptance must resolve its installed idd-plan dependency" >&2; exit 1; }
grep -q 'sibling `idd-plan`, `idd-issue`, `idd`, `idd-land`, and `idd-acceptance`' "$agents_root/idd-auto/SKILL.md" || {
  echo "idd-auto must declare its complete installed dependency set" >&2; exit 1; }
grep -q 'explicit target or current checkout' "$agents_root/idd-evolve/SKILL.md" || {
  echo "idd-evolve must mutate an explicit methodology checkout" >&2; exit 1; }

RESOLVE_PRD_PAIR_SCRIPT="$agents_root/idd-plan/scripts/resolve-prd-pair.sh" \
  bash "$root/scripts/test-resolve-prd-pair.sh"
INIT_PRD_SCRIPT="$agents_root/idd-plan/scripts/init-prd.sh" \
  bash "$root/scripts/test-init-prd.sh"
INIT_IMPLEMENTATION_SCRIPT="$agents_root/idd-plan/scripts/init-implementation.sh" \
  bash "$root/scripts/test-init-implementation.sh"
LAND_SCRIPT="$agents_root/idd-land/scripts/land.sh" \
  bash "$root/scripts/test-land.sh"
TRACKER_GATE_SCRIPT="$agents_root/idd-plan/scripts/tracker-gate.sh" \
  bash "$root/scripts/test-tracker-gate.sh"
MANIFEST_SCRIPT="$agents_root/idd-plan/scripts/manifest.sh" \
  bash "$root/scripts/test-manifest.sh"
STATIC_GATE_SCRIPT="$agents_root/idd-acceptance/scripts/static-gate.sh" \
  bash "$root/scripts/test-static-gate.sh"
PRD_FOLD_GATE_SCRIPT="$agents_root/idd-plan/scripts/prd-fold-gate.sh" \
  bash "$root/scripts/test-prd-fold-gate.sh"
bash "$agents_root/idd-publish/scripts/test-scan-exposure.sh"

grep -q 'npx skills add' "$root/README.md" || { echo "Missing ecosystem install command" >&2; exit 1; }
grep -q 'Selective install' "$root/README.md" || { echo "Missing selective-install documentation" >&2; exit 1; }
grep -q 'Composite dependencies' "$root/README.md" || { echo "Missing composite dependency documentation" >&2; exit 1; }
grep -q 'Development fallback' "$root/README.md" || { echo "Missing development-fallback warning" >&2; exit 1; }

echo "portable skill installation valid"
