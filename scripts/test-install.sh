#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
skill_count="$(find "$root/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
expected_links="$((skill_count * 3))"

assert_no_links() {
  local path="$1"
  [ -z "$(find "$path" -type l -print -quit)" ] || { echo "Unexpected partial installation under $path" >&2; exit 1; }
}

# Every conflict is reported before mutation, including conflicts that the old
# skill-by-skill loop would have encountered only after creating earlier links.
conflict_home="$work/conflict-home"
mkdir -p "$conflict_home/.claude/skills" "$conflict_home/codex/skills"
: >"$conflict_home/.claude/skills/idd"
: >"$conflict_home/codex/skills/idd-auto"
if HOME="$conflict_home" CODEX_HOME="$conflict_home/codex" bash "$root/scripts/install.sh" >"$work/conflict.out" 2>"$work/conflict.err"; then
  echo "Conflicting installation must fail" >&2
  exit 1
fi
grep -Fq "$conflict_home/.claude/skills/idd" "$work/conflict.err"
grep -Fq "$conflict_home/codex/skills/idd-auto" "$work/conflict.err"
assert_no_links "$conflict_home"

# A clean run installs every link, and an exact rerun is a no-op.
clean_home="$work/clean-home"
mkdir -p "$clean_home"
HOME="$clean_home" CODEX_HOME="$clean_home/codex" bash "$root/scripts/install.sh" >"$work/clean.out"
[ "$(find "$clean_home" -type l | wc -l | tr -d ' ')" -eq "$expected_links" ]
for source_dir in "$root"/skills/*; do
  name="$(basename "$source_dir")"
  for dest in \
    "$clean_home/.agents/skills/$name" \
    "$clean_home/.claude/skills/$name" \
    "$clean_home/codex/skills/$name"; do
    [ -L "$dest" ] && [ "$(readlink "$dest")" = "$source_dir" ] || { echo "Invalid installed link: $dest" >&2; exit 1; }
  done
done
HOME="$clean_home" CODEX_HOME="$clean_home/codex" bash "$root/scripts/install.sh" >"$work/rerun.out"
[ "$(find "$clean_home" -type l | wc -l | tr -d ' ')" -eq "$expected_links" ]
if grep -q '^Installed:' "$work/rerun.out"; then
  echo "Idempotent rerun created a link" >&2
  exit 1
fi

# Inject a deterministic creation failure after three successful links. Only the
# invocation-created links may be removed during rollback.
failure_home="$work/failure-home"
mkdir -p "$failure_home/.agents/skills" "$work/bin"
preexisting_link="$failure_home/.agents/skills/idd"
ln -s "$root/skills/idd" "$preexisting_link"
real_ln="$(command -v ln)"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'count=0' \
  '[ ! -f "$FAIL_LN_STATE" ] || count="$(cat "$FAIL_LN_STATE")"' \
  'count=$((count + 1))' \
  'printf "%s\n" "$count" >"$FAIL_LN_STATE"' \
  '[ "$count" -ne "$FAIL_LN_AT" ] || exit 70' \
  'exec "$REAL_LN" "$@"' >"$work/bin/ln"
chmod +x "$work/bin/ln"
if PATH="$work/bin:$PATH" REAL_LN="$real_ln" FAIL_LN_STATE="$work/ln-count" FAIL_LN_AT=4 \
  HOME="$failure_home" CODEX_HOME="$failure_home/codex" bash "$root/scripts/install.sh" >"$work/failure.out" 2>"$work/failure.err"; then
  echo "Injected link-creation failure must fail" >&2
  exit 1
fi
grep -q '^Rolled back:' "$work/failure.err"
[ "$(find "$failure_home" -type l | wc -l | tr -d ' ')" -eq 1 ] || { echo "Rollback left invocation-created links" >&2; exit 1; }
[ -L "$preexisting_link" ] && [ "$(readlink "$preexisting_link")" = "$root/skills/idd" ] || {
  echo "Rollback changed the pre-existing exact link" >&2; exit 1; }

echo "transactional symlink installation valid"
