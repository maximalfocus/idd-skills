#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="${INTEGRATION_BRANCH_SCRIPT:-$root/skills/idd-plan/scripts/integration-branch.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
command -v jq >/dev/null || { echo "integration-branch tests require jq" >&2; exit 1; }
mkdir -p "$tmp/bin"
export BRANCH_TEST_ROOT="$tmp"
export BRANCH_TEST_GIT="$(command -v git)"
export PATH="$tmp/bin:$PATH"

# A fake gh keyed on the API path: GETs answer from state files, mutations record
# their JSON body and move the state the way GitHub would. Any rulesets call fails
# the suite: the script never applies, reads, or checks branch protection.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${BRANCH_TEST_ROOT:?}"
if [ "$1 $2" = "repo view" ]; then
  touch "$root/repo-viewed"; echo maximalfocus/current; exit 0
fi
if [ "$1 $2" = "pr list" ]; then
  [ ! -f "$root/refuse-list" ] || { echo "PR list denied" >&2; exit 1; }
  cat "$root/open-prs" 2>/dev/null || true; exit 0
fi
if [ "$1 $2" = "pr edit" ]; then
  if [ -f "$root/refuse-edit" ] &&
    { [ ! -s "$root/refuse-edit" ] || [ "$(cat "$root/refuse-edit")" = "$3" ]; }; then
    echo "PR edit denied" >&2; exit 1
  fi
  echo "EDIT PR $3" >> "$root/calls"
  awk -v pr="$3" '$0 != pr' "$root/open-prs" > "$root/remaining-prs"
  mv "$root/remaining-prs" "$root/open-prs"
  echo "$3 $*" >> "$root/retargeted"; exit 0
fi
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
  *rulesets*|*/protection*) echo "unexpected protection call: $method $path" >&2; exit 2;;
  "PATCH repos/"*)
    body="$(cat)"; printf '%s' "$body" > "$root/patch-body"
    jq -r .default_branch <<<"$body" > "$root/default-branch";;
  "POST repos/"*"/git/refs") cat > "$root/ref-body"; touch "$root/branch-dev";;
  "GET repos/"*"/branches/"*)
    name="${path#*/branches/}" # a branch name may hold slashes
    # An empty name selects the list endpoint, not a missing branch.
    [ -n "$name" ] || { echo '[]'; exit 0; }
    [ -f "$root/branch-${name//\//_}" ] || { echo "gh: Branch not found (HTTP 404)" >&2; exit 1; }
    echo "$name";;
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
cat > "$tmp/bin/git" <<'FAKE'
#!/usr/bin/env bash
for operation in fetch current status switch config discovery; do
  [ -f "$BRANCH_TEST_ROOT/refuse-$operation" ] || continue
  case "$operation $*" in
    fetch*' fetch '*|current*' --show-current'|status*' --porcelain'|switch*' switch '*|\
      config*' config '*|discovery*' rev-parse --git-dir')
      echo "git $operation failed" >&2
      [ "$operation" != config ] || exit 128 # exit 1 would mean an unset key
      exit 1;;
  esac
done
exec "$BRANCH_TEST_GIT" "$@"
FAKE
chmod +x "$tmp/bin/git"

fresh() {
  rm -f "$tmp"/{calls,patch-body,refuse-writes,default-branch,ref-body,open-prs,retargeted} \
    "$tmp"/branch-* "$tmp"/refuse-* "$tmp/repo-viewed"
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
for operation in list edit; do
  fresh; echo 5 > "$tmp/open-prs"; touch "$tmp/refuse-$operation"
  refuses "a failed PR $operation" "PR $operation denied" bash "$script" integrate example/open
  rm "$tmp/refuse-$operation" "$tmp/calls"
  bash "$script" integrate example/open >/dev/null
  [ ! -s "$tmp/open-prs" ] || fail "integrate retry must finish retargeting"
  ! grep -qE '^(POST|PATCH) ' "$tmp/calls" || fail "retry must not recreate dev or reset default"
done

# --- ensure integrates a brownfield repository unless it opts out ---------------
fresh
git init -q "$tmp/co"; git -C "$tmp/co" commit -q --allow-empty -m base
git -C "$tmp/co" branch -M main
git init -q --bare "$tmp/origin.git"
git -C "$tmp/co" remote add origin "$tmp/origin.git"
git -C "$tmp/co" push -q origin main main:dev
ensure_mode() { (cd "$tmp/co" && bash "$script" "$@"); }
ensure() { ensure_mode ensure "$@"; }
out="$(ensure example/open 2>/dev/null)"
[ "$out" = "integration=dev release=main" ] || fail "ensure must integrate by default: $out"
[ "$(git -C "$tmp/co" branch --show-current)" = dev ] || fail "ensure must switch main to dev"
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

# Even an already-integrated opt-out or PRD must not retarget PRs or fetch.
echo dev > "$tmp/default-branch"; touch "$tmp/branch-dev" "$tmp/refuse-fetch"
echo 9 > "$tmp/open-prs"
printf 'Integration-branch: main\n' > "$tmp/co/AGENTS.md"
ensure example/open >/dev/null
no_writes "an already-integrated opt-out"
rm "$tmp/co/AGENTS.md"
ensure example/open-prd >/dev/null
no_writes "an already-integrated -prd"
[ "$(cat "$tmp/open-prs")" = 9 ] || fail "opt-out and PRD must leave PRs alone"

# Partial adoption is retried even after GitHub already reports dev/main.
for operation in edit fetch switch; do
  fresh; git -C "$tmp/co" switch -q main
  printf '5\n6\n' > "$tmp/open-prs"
  echo 6 > "$tmp/refuse-$operation"
  case "$operation" in edit) message='PR edit denied';; *) message="git $operation failed";; esac
  refuses "partial adoption at $operation" "$message" ensure example/open
  [ "$(cat "$tmp/default-branch")" = dev ] || fail "failure must follow default-branch change"
  [ "$(git -C "$tmp/co" branch --show-current)" = main ] || fail "failure must leave main"
  rm "$tmp/refuse-$operation" "$tmp/calls"
  out="$(ensure example/open)"
  [ "$out" = 'integration=dev release=main' ] || fail "retry summary: $out"
  [ ! -s "$tmp/open-prs" ] || fail "ensure retry must finish PR retargeting after $operation"
  [ "$(git -C "$tmp/co" branch --show-current)" = dev ] || fail "retry must switch to dev"
  [ "$(wc -l < "$tmp/retargeted" | tr -d ' ')" = 2 ] || fail "retarget each PR exactly once"
  ! grep -qE '^(POST|PATCH) ' "$tmp/calls" || fail "ensure retry must not reset remote branches"
done

fresh; mkdir "$tmp/co/AGENTS.md"
refuses "unreadable instructions" "AGENTS.md" ensure example/open
no_writes "unreadable instructions"
rmdir "$tmp/co/AGENTS.md"
for operation in fetch current status; do
  fresh; git -C "$tmp/co" switch -q main; touch "$tmp/refuse-$operation"
  refuses "a failed checkout $operation" "git $operation failed" ensure example/open
  rm "$tmp/refuse-$operation"
  [ "$(git -C "$tmp/co" branch --show-current)" = main ] || fail "failed read must not switch"
done

# --- a checkout that names its integration branch is read, never reshaped ---------
# Every write path is armed to fail or be seen: an open main-based PR, a refused PR
# list, fetch, and switch. The only call allowed is the read of the named branch.
named() { git -C "$tmp/co" config --local idd.integrationBranch "$1"; }
fresh; git -C "$tmp/co" switch -q main
named ai/work; touch "$tmp/branch-ai_work"
echo 5 > "$tmp/open-prs"; touch "$tmp/refuse-list" "$tmp/refuse-fetch" "$tmp/refuse-switch"
for mode in ensure show; do
  out="$(ensure_mode "$mode" example/open)"
  [ "$out" = "integration=ai/work release=none" ] || fail "named $mode: $out"
done
[ "$(cat "$tmp/calls")" = "GET repos/example/open/branches/ai/work
GET repos/example/open/branches/ai/work" ] ||
  fail "a named branch allows only its own read: $(cat "$tmp/calls")"
[ ! -f "$tmp/default-branch" ] && [ ! -f "$tmp/branch-dev" ] && [ ! -f "$tmp/retargeted" ] ||
  fail "a named branch must leave the repository as it is"
[ "$(cat "$tmp/open-prs")" = 5 ] || fail "a named branch must leave open PRs alone"
[ "$(git -C "$tmp/co" branch --show-current)" = main ] || fail "a named branch must not switch"
refuses "integrate in a naming checkout" "integrate refuses" ensure_mode integrate example/open
refuses "a named branch on a -prd" "stays single-branch" ensure_mode ensure example/open-prd
rm "$tmp/branch-ai_work"
for mode in show ensure; do
  refuses "a named branch the repository lacks in $mode" "does not have" \
    ensure_mode "$mode" example/open
done
named ""
for mode in show ensure; do
  refuses "an empty named branch in $mode" "does not have" ensure_mode "$mode" example/open
done
named ai/work; touch "$tmp/branch-ai_work" "$tmp/refuse-config"
for mode in show ensure integrate; do
  refuses "an unreadable git config in $mode" "Cannot read idd.integrationBranch" \
    ensure_mode "$mode" example/open
done
no_writes "every refused naming checkout"
[ ! -f "$tmp/default-branch" ] || fail "a refused naming checkout must not move the default branch"

# Unsetting the key restores integration on dev.
fresh; git -C "$tmp/co" config --local --unset idd.integrationBranch
out="$(ensure example/open 2>/dev/null)"
[ "$out" = "integration=dev release=main" ] || fail "an unset key must integrate again: $out"
grep -q '^PATCH repos/example/open$' "$tmp/calls" || fail "an unset key must make dev default"

# Explicit repository arguments still work outside any local repository.
mkdir "$tmp/outside"
for mode in show integrate ensure; do
  fresh; touch "$tmp/refuse-fetch" "$tmp/refuse-switch"
  out="$(cd "$tmp/outside" && bash "$script" "$mode" example/open 2>/dev/null)"
  case "$mode" in
    show) [ "$out" = "integration=main release=none" ] || fail "outside show: $out"
      no_writes "outside show";;
    integrate) [ "$out" = "example/open integrates on dev; main is the release branch" ] ||
      fail "outside integrate: $out";;
    ensure) [ "$out" = "integration=dev release=main" ] || fail "outside ensure: $out";;
  esac
  if [ "$mode" != show ]; then
    [ "$(cat "$tmp/default-branch")" = dev ] || fail "outside $mode must adopt dev"
    [ -f "$tmp/ref-body" ] || fail "outside $mode must create dev"
  fi
done

# A bare repository has local config even though show-toplevel cannot succeed.
fresh; git init -q --bare "$tmp/bare"
git -C "$tmp/bare" config --local idd.integrationBranch ai/work
touch "$tmp/branch-ai_work" "$tmp/refuse-fetch" "$tmp/refuse-switch"
bare_mode() { (cd "$tmp/bare" && bash "$script" "$@"); }
refuses "integrate in a bare naming repository" "integrate refuses" \
  bare_mode integrate example/open
for mode in show ensure; do
  out="$(bare_mode "$mode" example/open)"
  [ "$out" = "integration=ai/work release=none" ] || fail "bare $mode: $out"
done
no_writes "a bare naming repository"
[ ! -f "$tmp/default-branch" ] && [ ! -f "$tmp/ref-body" ] || fail "bare must not adopt"

# Failed discovery is not absence; every mode stops before any GitHub call.
fresh; named ai/work; touch "$tmp/branch-ai_work" "$tmp/refuse-discovery"
for mode in show ensure integrate; do
  refuses "failed repository discovery in $mode" "Cannot discover the git repository" \
    ensure_mode "$mode" example/open
done
no_writes "failed repository discovery"
[ ! -s "$tmp/calls" ] || fail "failed discovery must stop before GitHub"
rm "$tmp/refuse-discovery"

# Unsafe names stop before any GitHub call, even without an explicit repository.
git -C "$tmp/co" switch -q main
for branch in 'ai#work' 'ai?work' 'ai%work' 'ai..work' 'ai//work' 'ai.lock' \
  '-work' '/work' '.work' 'ai:work' 'ai work' $'ai\nwork' \
  $'ai/work\n' $'ai/work\n\n' $'\n' $'ai/work\r\n'; do
  fresh; named "$branch"; touch "$tmp/branch-ai_work"
  for mode in show ensure integrate; do
    refuses "unsafe name in $mode" "Unsafe idd.integrationBranch" \
      ensure_mode "$mode" example/open
    refuses "unsafe name before repository resolution in $mode" "Unsafe idd.integrationBranch" \
      ensure_mode "$mode"
  done
  [ ! -s "$tmp/calls" ] && [ ! -f "$tmp/repo-viewed" ] ||
    fail "unsafe names must stop before GitHub"
  [ "$(git -C "$tmp/co" branch --show-current)" = main ] || fail "unsafe name switched checkout"
done
fresh; named ai/work.v1_test-2; touch "$tmp/branch-ai_work.v1_test-2"
out="$(ensure_mode show example/open)"
[ "$out" = "integration=ai/work.v1_test-2 release=none" ] || fail "safe name: $out"

# Prove the regex runs in C even where no hostile locale is installed. POSIX always exists.
cat > "$tmp/locale-proof" <<'PROOF'
check_branch_locale() {
  case "$BASH_COMMAND" in
    '[[ "$named" =~ '*)
      [ "${LC_ALL:-}" = C ] || { echo "branch regex must run in C" >&2; exit 1; }
      touch "$BRANCH_TEST_ROOT/locale-checked";;
  esac
}
trap check_branch_locale DEBUG
PROOF
locale_mode() {
  (cd "$tmp/co" && LC_ALL=POSIX BASH_ENV="$tmp/locale-proof" bash "$script" "$@")
}
fresh; named ai/work; touch "$tmp/branch-ai_work"
for mode in show ensure; do
  out="$(locale_mode "$mode" example/open)"
  [ "$out" = "integration=ai/work release=none" ] || fail "C validation changed a safe name"
done
[ -f "$tmp/locale-checked" ] || fail "locale proof did not observe the branch regex"
for branch in 'é' $'\351'; do
  fresh; named "$branch"; rm "$tmp/locale-checked"
  for mode in show ensure integrate; do
    refuses "non-ASCII branch in $mode" "Unsafe idd.integrationBranch" locale_mode "$mode"
  done
  [ -f "$tmp/locale-checked" ] || fail "non-ASCII validation was not observed"
  [ ! -s "$tmp/calls" ] && [ ! -f "$tmp/repo-viewed" ] || fail "non-ASCII name reached GitHub"
done

# A malformed local config is also a read error, not an unset key.
fresh; printf '\n[broken\n' >> "$tmp/co/.git/config"
for mode in show ensure integrate; do
  refuses "malformed local config in $mode" "Cannot" ensure_mode "$mode" example/open
done
no_writes "malformed local config"
[ ! -s "$tmp/calls" ] || fail "malformed config must stop before GitHub"

echo "integration-branch tests passed"
