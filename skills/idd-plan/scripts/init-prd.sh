#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: init-prd.sh REPOSITORY_PATH OWNER/PROJECT-prd" >&2; exit 64; }
[ "$#" -eq 2 ] || usage
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="$1"; repo="$2"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+-prd$ ]] || usage
[ -d "$target" ] || { echo "Missing PRD directory: $target" >&2; exit 1; }
target="$(cd "$target" && pwd -P)"
[ -f "$target/PRD.md" ] && [ -f "$target/PROGRESS.md" ] || {
  echo "PRD.md and PROGRESS.md are required" >&2; exit 1;
}
extra="$(find "$target" -mindepth 1 -maxdepth 1 ! -name PRD.md ! -name PROGRESS.md ! -name .git -print -quit)"
[ -z "$extra" ] || { echo "Unexpected bootstrap path: $extra" >&2; exit 1; }
gh auth status >/dev/null

if [ ! -d "$target/.git" ]; then
  git -C "$target" init -q -b main
  git -C "$target" add PRD.md PROGRESS.md
  git -C "$target" commit -qm "docs: establish product requirements and progress tracker"
else
  [ -z "$(git -C "$target" status --porcelain)" ] || { echo "PRD repository is dirty" >&2; exit 1; }
fi
# The initial commit is the one direct push a repository gets, so it carries no wide line.
(cd "$target" && bash "$here/line-width.sh" check --root HEAD >/dev/null)

expected="https://github.com/$repo.git"
if git -C "$target" remote get-url origin >/dev/null 2>&1; then
  actual="$(git -C "$target" remote get-url origin)"
  [ "$actual" = "$expected" ] || { echo "Unexpected origin: $actual" >&2; exit 1; }
  gh repo view "$repo" >/dev/null
  remote_main="$(git -C "$target" ls-remote --heads origin refs/heads/main)"
  remote_main="${remote_main%%[[:space:]]*}"
  if [ -n "$remote_main" ]; then
    [ "$remote_main" = "$(git -C "$target" rev-parse refs/heads/main)" ] || {
      echo "Bootstrap already published; route subsequent changes through a pull request" >&2; exit 1; }
  else
    [ "$(git -C "$target" rev-list --count main)" = 1 ] || {
      echo "Bootstrap requires one initial commit; inspect local history before retrying" >&2; exit 1; }
    git -C "$target" push -u origin main
  fi
else
  gh repo view "$repo" >/dev/null 2>&1 && { echo "GitHub repository already exists: $repo" >&2; exit 1; }
  gh repo create "$repo" --private --description "Private requirements and delivery progress for ${repo##*/}." --source "$target" --remote origin --push
fi

readback="$(gh repo view "$repo" --json nameWithOwner,visibility,url --jq '[.nameWithOwner,.visibility,.url]|@tsv')"
[[ "$readback" == "$repo"$'\tPRIVATE\t'* ]] || { echo "Private remote verification failed: $readback" >&2; exit 1; }
# From here on the default branch changes only through a squash-merged pull request.
bash "$here/protect-main.sh" apply "$repo" >&2
printf 'repository=%s\ncommit=%s\n' "${readback##*$'\t'}" "$(git -C "$target" rev-parse HEAD)"
