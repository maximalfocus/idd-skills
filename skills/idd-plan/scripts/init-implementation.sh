#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: init-implementation.sh PRD_REPOSITORY_PATH" >&2; exit 64; }
[ "$#" -eq 1 ] || usage
prd="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a PRD repository: $1" >&2; exit 1; }
prd="$(cd "$prd" && pwd -P)"
[ -f "$prd/PRD.md" ] && [ -f "$prd/PROGRESS.md" ] || { echo "PRD.md and PROGRESS.md are required" >&2; exit 1; }
[ -z "$(git -C "$prd" status --porcelain)" ] || { echo "PRD repository is dirty" >&2; exit 1; }

normalize_github_remote() {
  local url="${1%.git}"
  case "$url" in
    https://github.com/*) printf '%s\n' "${url#https://github.com/}" ;;
    http://github.com/*) printf '%s\n' "${url#http://github.com/}" ;;
    git@github.com:*) printf '%s\n' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s\n' "${url#ssh://git@github.com/}" ;;
    *) echo "Unsupported GitHub origin: $url" >&2; return 1 ;;
  esac
}

prd_repo="$(normalize_github_remote "$(git -C "$prd" remote get-url origin)")"
owner="${prd_repo%%/*}"; prd_name="${prd_repo#*/}"
[[ "$prd_name" == *-prd ]] || { echo "PRD origin must end in -prd: $prd_repo" >&2; exit 1; }
impl_name="${prd_name%-prd}"; impl_repo="$owner/$impl_name"
parent="$(dirname "$prd")"; impl="$parent/$impl_name"
[ ! -e "$impl" ] || { echo "Implementation path already exists: $impl" >&2; exit 1; }
gh auth status >/dev/null

created=false
if gh repo view "$impl_repo" >/dev/null 2>&1; then
  (cd "$parent" && gh repo clone "$impl_repo" "$impl_name")
else
  (cd "$parent" && gh repo create "$impl_repo" --private --add-readme \
    --description "Private implementation repository for $impl_name." --clone)
  created=true
fi

[ -d "$impl/.git" ] || { echo "Implementation clone was not created: $impl" >&2; exit 1; }
pair="$(bash "$(dirname "${BASH_SOURCE[0]}")/resolve-prd-pair.sh" "$prd")"
expected="implementation=$impl
prd=$prd"
[ "$pair" = "$expected" ] || { echo "Implementation pair readback failed" >&2; exit 1; }
[ -z "$(git -C "$impl" status --porcelain)" ] || { echo "Implementation checkout is dirty" >&2; exit 1; }

readback="$(gh repo view "$impl_repo" --json nameWithOwner,visibility,url,defaultBranchRef --jq '[.nameWithOwner,.visibility,.url,.defaultBranchRef.name]|@tsv')"
[[ "$readback" == "$impl_repo"$'\t'* ]] || { echo "Implementation remote readback failed: $readback" >&2; exit 1; }
if [ "$created" = true ]; then
  [[ "$readback" == "$impl_repo"$'\tPRIVATE\t'* ]] || { echo "Created implementation repository is not private: $readback" >&2; exit 1; }
fi
default_branch="${readback##*$'\t'}"
[ -n "$default_branch" ] && [ "$(git -C "$impl" branch --show-current)" = "$default_branch" ] || {
  echo "Implementation default branch checkout mismatch" >&2; exit 1;
}
printf 'implementation=%s\nrepository=%s\nvisibility=%s\ncommit=%s\ncreated=%s\n' \
  "$impl" "$(cut -f3 <<<"$readback")" "$(cut -f2 <<<"$readback")" \
  "$(git -C "$impl" rev-parse HEAD)" "$created"
