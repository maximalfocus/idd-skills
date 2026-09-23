#!/usr/bin/env bash
set -euo pipefail

usage() { echo "usage: resolve-prd-pair.sh [REPOSITORY_PATH]" >&2; exit 64; }
[ "$#" -le 1 ] || usage
start="${1:-.}"
root="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null)" || { echo "Not in a git repository: $start" >&2; exit 1; }
root="$(cd "$root" && pwd -P)"
parent="$(dirname "$root")"

normalize_github_remote() {
  local url="$1"
  url="${url%.git}"
  case "$url" in
    https://github.com/*) printf '%s\n' "${url#https://github.com/}" ;;
    http://github.com/*) printf '%s\n' "${url#http://github.com/}" ;;
    git@github.com:*) printf '%s\n' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s\n' "${url#ssh://git@github.com/}" ;;
    *) echo "Unsupported GitHub origin: $url" >&2; return 1 ;;
  esac
}

root_repo="$(normalize_github_remote "$(git -C "$root" remote get-url origin)")"
owner="${root_repo%%/*}"
name="${root_repo#*/}"
if [[ "$name" == *-prd ]] && [ -f "$root/PRD.md" ] && [ -f "$root/PROGRESS.md" ]; then
  prd="$root"
  impl_name="${name%-prd}"
  impl="$parent/$impl_name"
else
  impl="$root"
  impl_name="$name"
  prd="$parent/$impl_name-prd"
fi

# No sibling PRD means this project has not opted into IDD planning/reconciliation.
[ -e "$prd" ] || exit 3
git -C "$impl" rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "Missing sibling implementation repository: $impl" >&2; exit 1;
}
git -C "$prd" rev-parse --show-toplevel >/dev/null 2>&1 || {
  echo "Associated PRD path is not a git repository: $prd" >&2; exit 1;
}
[ -f "$prd/PRD.md" ] && [ -f "$prd/PROGRESS.md" ] || {
  echo "Associated PRD repository must contain PRD.md and PROGRESS.md: $prd" >&2; exit 1;
}

impl_repo="$(normalize_github_remote "$(git -C "$impl" remote get-url origin)")"
prd_repo="$(normalize_github_remote "$(git -C "$prd" remote get-url origin)")"
impl_owner="${impl_repo%%/*}"
[ "$impl_repo" = "$impl_owner/$impl_name" ] || {
  echo "Implementation origin $impl_repo does not match expected */$impl_name" >&2; exit 1;
}
# A PRD under another owner is associated only when the implementation checkout's local git
# config names it exactly (git config idd.prdRepo OWNER/NAME-prd); nothing is committed for it.
optin="$(git -C "$impl" config --get idd.prdRepo || true)"
if [ "$prd_repo" != "$impl_owner/$impl_name-prd" ] \
  && { [ "$prd_repo" != "$optin" ] || [ "${prd_repo#*/}" != "$impl_name-prd" ]; }; then
  echo "PRD origin $prd_repo does not match expected $impl_owner/$impl_name-prd" \
    "or the implementation's idd.prdRepo" >&2; exit 1
fi

printf 'implementation=%s\nprd=%s\n' "$impl" "$prd"
