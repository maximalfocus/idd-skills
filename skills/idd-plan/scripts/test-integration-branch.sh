#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="${INTEGRATION_BRANCH_SCRIPT:-$root/skills/idd-plan/scripts/integration-branch.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
command -v jq >/dev/null || { echo "integration-branch tests require jq" >&2; exit 1; }
mkdir -p "$tmp/bin"
export BRANCH_TEST_ROOT="$tmp"
export PATH="$tmp/bin:$PATH"

# A fake gh keyed on the API path: GETs answer from state files, mutations record
# their JSON body and move the state the way GitHub would. Any rulesets call fails
# the suite: the script never applies, reads, or checks branch protection.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${BRANCH_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then echo maximalfocus/current; exit 0; fi
if [ "$1 $2" = "pr list" ]; then cat "$root/open-prs" 2>/dev/null || true; exit 0; fi
if [ "$1 $2" = "pr edit" ]; then echo "$3 $*" >> "$root/retargeted"; exit 0; fi
[ "$1" = api ] || { echo "unexpected gh: $*" >&2; exit 2; }
shift
method=GET; path=""; jq=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --method) method="$2"; shift;;
    --input) shift;;
    --jq) jq="$2"; shift;;
    *) [ -z "$path" ] && path="$1";;
  esac
  shift
done
echo "$method $path" >> "$root/calls"
if [ "$method" != GET ] && [ -f "$root/refuse-writes" ]; then
  echo "gh: Resource not accessible by integration (HTTP 403)" >&2; exit 1
fi
case "$method $path" in
  *rulesets*) echo "unexpected rulesets call: $method $path" >&2; exit 2;;
  "PATCH repos/"*)
    body="$(cat)"; printf '%s' "$body" > "$root/patch-body"
    jq -r .default_branch <<<"$body" > "$root/default-branch";;
  "POST repos/"*"/git/refs") cat > "$root/ref-body"; touch "$root/branch-dev";;
  "GET repos/"*"/branches/"*)
    [ -f "$root/branch-${path##*/}" ] || { echo "gh: Branch not found (HTTP 404)" >&2; exit 1; }
    echo "${path##*/}";;
  "GET repos/"*"/git/ref/heads/"*) echo 0123abc;;
  "GET repos/"*)
    case "$jq" in
      .default_branch) cat "$root/default-branch" 2>/dev/null || echo main;;
      *) echo "unexpected repository read: $jq" >&2; exit 2;;
    esac;;
  *) echo "unexpected gh api: $method $path" >&2; exit 2;;
esac
FAKE
chmod +x "$tmp/bin/gh"

fresh() {
  rm -f "$tmp"/{calls,patch-body,refuse-writes,default-branch,ref-body,open-prs,retargeted} \
    "$tmp"/branch-*
  touch "$tmp/branch-main"
}
fail() { echo "$*" >&2; exit 1; }
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then fail "integration-branch accepted $desc"; fi
  case "$err" in
    *"$want"*) ;;
    *) fail "integration-branch rejected $desc for the wrong reason: $err";;
  esac
}
no_writes() { # $1 = context
  ! grep -qv '^GET ' "$tmp/calls" 2>/dev/null || fail "$1 must not write: $(cat "$tmp/calls")"
}

# --- show reads the branch strategy and writes nothing ----------------------------
fresh
out="$(bash "$script" show example/open)"
[ "$out" = "integration=main release=none" ] || fail "single-branch show: $out"
echo dev > "$tmp/default-branch"; touch "$tmp/branch-dev"
out="$(bash "$script" show example/open)"
[ "$out" = "integration=dev release=main" ] || fail "show must report dev and main: $out"
rm "$tmp/branch-main"
out="$(bash "$script" show example/open)"
[ "$out" = "integration=dev release=none" ] || fail "dev without main has no release: $out"
no_writes show
fresh
out="$(bash "$script" show)"
[ "$out" = "integration=main release=none" ] || fail "show must default to the checkout: $out"
grep -q '^GET repos/maximalfocus/current$' "$tmp/calls" ||
  fail "show must read the checkout repository: $(cat "$tmp/calls")"

# --- usage ---------------------------------------------------------------------
for mode in apply verify enable; do
  refuses "the mode $mode" "usage:" bash "$script" "$mode" example/open
done
refuses "a bare repository name" "usage:" bash "$script" show open

# --- integrate creates dev from main, makes it default, retargets open PRs ------
fresh; printf '5\n' > "$tmp/open-prs"
out="$(bash "$script" integrate example/open 2>"$tmp/err")" || fail "$(cat "$tmp/err")"
[ "$out" = "example/open integrates on dev; main is the release branch" ] ||
  fail "integrate summary: $out"
[ "$(cat "$tmp/default-branch")" = dev ] || fail "integrate must make dev the default branch"
[ "$(jq -c . "$tmp/patch-body")" = '{"default_branch":"dev","allow_merge_commit":true}' ] ||
  fail "integrate must set only the default branch and merge commits: $(cat "$tmp/patch-body")"
grep -Fq '"ref":"refs/heads/dev","sha":"0123abc"' "$tmp/ref-body" ||
  fail "integrate must create dev at main"
grep -q '^5 .*--base dev' "$tmp/retargeted" || fail "integrate must retarget open PRs to dev"
rm "$tmp/ref-body" "$tmp/calls"; bash "$script" integrate example/open >/dev/null 2>&1
[ ! -f "$tmp/ref-body" ] || fail "a second integrate must not recreate dev"
no_writes "a second integrate"
echo master > "$tmp/default-branch"
refuses "integrating a non-main default" "integrate expects default branch main or dev" \
  bash "$script" integrate example/open
fresh; touch "$tmp/refuse-writes"
refuses "a refused write" "HTTP 403" bash "$script" integrate example/open
[ ! -f "$tmp/default-branch" ] || fail "a refused write must not move the default branch"
fresh; rm "$tmp/branch-main"; echo dev > "$tmp/default-branch"; touch "$tmp/branch-dev"
refuses "dev without main" "not dev and main" bash "$script" integrate example/open

# --- ensure integrates a brownfield repository unless it opts out ---------------
fresh
git init -q "$tmp/co"; git -C "$tmp/co" commit -q --allow-empty -m base
ensure() { (cd "$tmp/co" && bash "$script" ensure "$@"); }
out="$(ensure example/open 2>/dev/null)"
[ "$out" = "integration=dev release=main" ] || fail "ensure must integrate by default: $out"
rm "$tmp/calls"
out="$(ensure example/open 2>/dev/null)"
[ "$out" = "integration=dev release=main" ] || fail "ensure must be idempotent: $out"
no_writes "an integrated ensure"
fresh; printf 'Integration-branch: `main`\n' > "$tmp/co/AGENTS.md"
out="$(ensure example/open)"
[ "$out" = "integration=main release=none" ] && [ ! -f "$tmp/default-branch" ] ||
  fail "Integration-branch: main must opt out: $out"
no_writes "an opted-out ensure"
printf 'Integration-branch: trunk\n' > "$tmp/co/AGENTS.md"
refuses "an unknown integration branch" "must be dev or main" ensure example/open
rm "$tmp/co/AGENTS.md"
out="$(ensure example/open-prd)"
[ "$out" = "integration=main release=none" ] && [ ! -f "$tmp/default-branch" ] ||
  fail "a -prd repository stays single-branch: $out"
no_writes "a -prd ensure"

echo "integration-branch tests passed"
