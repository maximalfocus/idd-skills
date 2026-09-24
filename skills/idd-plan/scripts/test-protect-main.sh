#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="${PROTECT_MAIN_SCRIPT:-$root/skills/idd-plan/scripts/protect-main.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
command -v jq >/dev/null || { echo "protect-main tests require jq" >&2; exit 1; }
mkdir -p "$tmp/bin"
export PROTECT_TEST_ROOT="$tmp"
export PATH="$tmp/bin:$PATH"

# A fake gh keyed on the API path: GETs answer from state files, mutations record
# their JSON body and move the state the way GitHub would.
cat > "$tmp/bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -e
root="${PROTECT_TEST_ROOT:?}"
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
printf 'x' >> "$root/calls"
if { [ "$method" != GET ] && [ -f "$root/refuse-writes" ]; } || { [[ "$path" == */rulesets* ]] && [ -f "$root/refuse-rulesets" ]; }; then
  echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1
fi
rs() { # $1 = name, $2 = id file
  [ ! -f "$root/$2" ] || jq -n --arg n "$1" --argjson id "$(cat "$root/$2")" '{name:$n,id:$id}'
}
case "$method $path" in
  "PATCH repos/"*)
    body="$(cat)"
    if [[ "$body" == *default_branch* ]]; then
      jq -r .default_branch <<<"$body" > "$root/default-branch"
    else printf '%s' "$body" > "$root/patch-body"; cp "$root/patch-body" "$root/settings"; fi;;
  "POST repos/"*"/git/refs") cat > "$root/ref-body"; touch "$root/branch-dev";;
  "POST repos/"*"/rulesets")
    body="$(cat)"
    if [ "$(jq -r .name <<<"$body")" = protect-release ]; then
      printf '%s' "$body" > "$root/release-post-body"; echo 43 > "$root/release-ruleset-id"
      cp "$root/release-post-body" "$root/release-ruleset"
    else
      printf '%s' "$body" > "$root/post-body"; echo 42 > "$root/ruleset-id"
      cp "$root/post-body" "$root/ruleset"
    fi;;
  "PUT repos/"*"/rulesets/43")
    cat > "$root/release-put-body"; cp "$root/release-put-body" "$root/release-ruleset";;
  "PUT repos/"*"/rulesets/"*) cat > "$root/put-body"; cp "$root/put-body" "$root/ruleset";;
  "GET repos/"*"/rulesets/43") jq -r "$jq" "$root/release-ruleset";;
  "GET repos/"*"/rulesets/"*) jq -r "$jq" "$root/ruleset";;
  "GET repos/"*"/rulesets")
    { rs require-pull-request ruleset-id; rs protect-release release-ruleset-id; } |
      jq -s . | jq -r "$jq";;
  "GET repos/"*"/branches/"*)
    [ -f "$root/branch-${path##*/}" ] || { echo "gh: Branch not found (HTTP 404)" >&2; exit 1; }
    echo "${path##*/}";;
  "GET repos/"*"/git/ref/heads/"*) echo 0123abc;;
  "GET repos/"*)
    case "$jq" in
      .visibility) cat "$root/visibility";;
      .default_branch) cat "$root/default-branch" 2>/dev/null || echo main;;
      *) jq -r "$jq" "$root/settings";;
    esac;;
  *) echo "unexpected gh api: $method $path" >&2; exit 2;;
esac
FAKE
chmod +x "$tmp/bin/gh"
cat > "$tmp/protected-ruleset" <<'JSON'
{"name":"require-pull-request","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"required_linear_history"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":true,"allowed_merge_methods":["squash"]}}]}
JSON
settings_fixture() {
  jq -n --arg fields "$1" '$fields | split(" ") | {allow_squash_merge:(.[0]|fromjson),allow_merge_commit:(.[1]|fromjson),allow_rebase_merge:(.[2]|fromjson),delete_branch_on_merge:(.[3]|fromjson),squash_merge_commit_title:.[4],squash_merge_commit_message:.[5]}' > "$tmp/settings"
}

fresh() {
  rm -f "$tmp"/{calls,patch-body,post-body,put-body,ruleset-id,ruleset,refuse-writes} \
    "$tmp"/{refuse-rulesets,default-branch,ref-body,open-prs,retargeted} "$tmp"/branch-* \
    "$tmp"/release-*
  settings_fixture "$1"; echo public > "$tmp/visibility"; touch "$tmp/branch-main"
}
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "protect-main accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "protect-main rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
}

# --- verify fails closed on an unprotected repository -------------------------
fresh 'true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES'
refuses "an unprotected repository" "no ruleset named require-pull-request" bash "$script" verify example/open
refuses "drifted merge settings" "settings drift" bash "$script" verify example/open
# The repair names the script as installed, runnable from any checkout.
self="$(cd "$(dirname "$script")" && pwd)/$(basename "$script")"
refuses "an unprotected repository" "bash $self apply example/open" \
  bash "$script" verify example/open
[ ! -f "$tmp/patch-body" ] || { echo "verify must not mutate" >&2; exit 1; }

# --- apply creates the ruleset and reshapes the settings ----------------------
out="$(bash "$script" apply example/open)"
case "$out" in *"example/open default branch protected"*) ;; *) echo "unexpected apply output: $out" >&2; exit 1;; esac
[ -f "$tmp/post-body" ] || { echo "apply must POST a new ruleset" >&2; exit 1; }
[ ! -f "$tmp/put-body" ] || { echo "apply must not PUT before a ruleset exists" >&2; exit 1; }
for want in '"enforcement":"active"' '"bypass_actors":[]' '"~DEFAULT_BRANCH"' '"type":"deletion"' '"type":"non_fast_forward"' \
  '"type":"required_linear_history"' '"required_approving_review_count":0' '"required_review_thread_resolution":true' '"allowed_merge_methods":["squash"]'; do
  grep -Fq "$want" "$tmp/post-body" || { echo "ruleset body lacks $want" >&2; exit 1; }
done
for want in '"allow_merge_commit":false' '"allow_rebase_merge":false' '"allow_squash_merge":true' '"delete_branch_on_merge":true' \
  '"squash_merge_commit_title":"PR_TITLE"' '"squash_merge_commit_message":"PR_BODY"'; do
  grep -Fq "$want" "$tmp/patch-body" || { echo "settings body lacks $want" >&2; exit 1; }
done

# --- a second apply updates the existing ruleset in place ---------------------
rm -f "$tmp/post-body"
bash "$script" apply example/open >/dev/null
[ -f "$tmp/put-body" ] && [ ! -f "$tmp/post-body" ] || { echo "second apply must PUT the existing ruleset, not POST another" >&2; exit 1; }
bash "$script" verify example/open >/dev/null

# --- verify names each drift from the protected shape -------------------------
for mutation in \
  '.bypass_actors = [{actor_id:1,actor_type:"Integration",bypass_mode:"always"}]' \
  '.enforcement = "disabled"' \
  '.target = "tag"' \
  '.conditions.ref_name.exclude = ["~DEFAULT_BRANCH"]' \
  '.conditions.ref_name.include = ["refs/heads/other"]' \
  '(.rules[] | select(.type=="pull_request").parameters.require_code_owner_review) = true' \
  '(.rules[] | select(.type=="pull_request").parameters.require_last_push_approval) = true' \
  '(.rules[] | select(.type=="pull_request").parameters.required_approving_review_count) = 1' \
  '(.rules[] | select(.type=="pull_request").parameters.dismiss_stale_reviews_on_push) = false' \
  '(.rules[] | select(.type=="pull_request").parameters.required_review_thread_resolution) = false' \
  '(.rules[] | select(.type=="pull_request").parameters.allowed_merge_methods) = ["squash","merge"]' \
  '.rules |= map(select(.type != "deletion"))'; do
  jq "$mutation" "$tmp/protected-ruleset" > "$tmp/ruleset"
  refuses "$mutation" "ruleset drift" bash "$script" verify example/open
done
cp "$tmp/protected-ruleset" "$tmp/ruleset"
settings_fixture 'true true false true PR_TITLE PR_BODY'
refuses "merge commits re-enabled" "settings drift" bash "$script" verify example/open

# --- a private repository on GitHub Free names the plan limit ------------------
fresh 'true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES'; touch "$tmp/refuse-writes"; echo private > "$tmp/visibility"
refuses "a refused write on a private repository" "GitHub Free does not enforce rulesets on a private repository; make example/locked public" bash "$script" apply example/locked
echo public > "$tmp/visibility"
refuses "a refused write on a public repository" "HTTP 403" bash "$script" apply example/locked
err="$(bash "$script" apply example/locked 2>&1 >/dev/null || true)"
case "$err" in *"GitHub Free"*) echo "a public repository must not be told about the private plan limit" >&2; exit 1;; esac
rm -f "$tmp/refuse-writes"
# GitHub Free refuses even the rulesets READ on a private repository (observed live 2026-09-09),
# so a private repository never touches rulesets: apply sets the settings and defers, verify
# passes on the settings alone and says so, and both fail on drifted settings.
fresh 'true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES'; touch "$tmp/refuse-rulesets"; echo private > "$tmp/visibility"
refuses "a private repository with drifted settings" "settings drift" bash "$script" verify example/locked
out="$(bash "$script" apply example/locked 2>"$tmp/apply-err")"
grep -q "ruleset deferred: example/locked is private" "$tmp/apply-err" || { echo "apply on a private repository must say the ruleset is deferred" >&2; exit 1; }
case "$out" in *"ruleset DEFERRED while private"*) ;; *) echo "apply on a private repository must report the deferred state: $out" >&2; exit 1;; esac
[ -f "$tmp/patch-body" ] || { echo "apply on a private repository must still set the merge settings" >&2; exit 1; }
[ ! -f "$tmp/post-body" ] && [ ! -f "$tmp/put-body" ] || { echo "apply on a private repository must not write a ruleset" >&2; exit 1; }
out="$(bash "$script" verify example/locked)"
case "$out" in *"ruleset DEFERRED while private"*) ;; *) echo "verify on a private repository with good settings must pass as deferred: $out" >&2; exit 1;; esac
# Once the repository is public, the deferred ruleset is drift until apply is rerun.
echo public > "$tmp/visibility"; rm -f "$tmp/refuse-rulesets"
refuses "a newly public repository" "no ruleset named require-pull-request" bash "$script" verify example/locked
bash "$script" apply example/locked >/dev/null; [ -f "$tmp/post-body" ] || { echo "apply after going public must create the ruleset" >&2; exit 1; }
bash "$script" verify example/locked >/dev/null
# A refused rulesets call on a public repository surfaces gh's own error.
fresh 'true false false true PR_TITLE PR_BODY'; touch "$tmp/refuse-rulesets"
refuses "a refused rulesets read on a public repository" "HTTP 403" bash "$script" verify example/locked
rm -f "$tmp/refuse-rulesets"

# --- the repository defaults to the current checkout --------------------------
fresh 'true false false true PR_TITLE PR_BODY'; echo 7 > "$tmp/ruleset-id"; cp "$tmp/protected-ruleset" "$tmp/ruleset"
out="$(bash "$script" verify)"
case "$out" in "maximalfocus/current default branch protected"*) ;; *) echo "verify must default to the checkout repository: $out" >&2; exit 1;; esac

# --- usage ---------------------------------------------------------------------
refuses "an unknown mode" "usage:" bash "$script" enable example/open
refuses "a bare repository name" "usage:" bash "$script" verify open

# --- a dev integration branch adds a merge-only release ruleset on main ---------
fail() { echo "$*" >&2; exit 1; }
good='true false false true PR_TITLE PR_BODY'
fresh "$good"; echo 7 > "$tmp/ruleset-id"; cp "$tmp/protected-ruleset" "$tmp/ruleset"
out="$(bash "$script" show example/open)"
[ "$out" = "integration=main release=none" ] || fail "single-branch show: $out"
echo dev > "$tmp/default-branch"; touch "$tmp/branch-dev"
out="$(bash "$script" show example/open)"
[ "$out" = "integration=dev release=main" ] || fail "show must report dev and main: $out"
refuses "a release branch without its ruleset" "no ruleset named protect-release" \
  bash "$script" verify example/open
refuses "squash-only settings on a two-branch repository" "settings drift" \
  bash "$script" verify example/open
bash "$script" apply example/open >/dev/null
for want in '"refs/heads/main"' '"allowed_merge_methods":["merge"]' '"type":"deletion"' \
  '"type":"non_fast_forward"' '"bypass_actors":[]'; do
  grep -Fq "$want" "$tmp/release-post-body" || fail "release ruleset body lacks $want"
done
! grep -Fq required_linear_history "$tmp/release-post-body" ||
  fail "the release branch must accept merge commits"
grep -Fq '"allow_merge_commit":true' "$tmp/patch-body" ||
  fail "a release branch needs merge commits enabled"
out="$(bash "$script" verify example/open)"
case "$out" in
  *"main by merge-commit pull request only"*) ;;
  *) fail "two-branch verify: $out";;
esac
jq '(.rules[] | select(.type=="pull_request").parameters.allowed_merge_methods) = ["squash"]' \
  "$tmp/release-ruleset" > "$tmp/r" && mv "$tmp/r" "$tmp/release-ruleset"
refuses "a squash-only release ruleset" "ruleset drift: example/open ruleset protect-release" \
  bash "$script" verify example/open

# --- integrate creates dev from main, makes it default, retargets open PRs ------
fresh "$good"; printf '5\n' > "$tmp/open-prs"
bash "$script" integrate example/open >/dev/null 2>"$tmp/err" || fail "$(cat "$tmp/err")"
[ "$(cat "$tmp/default-branch")" = dev ] || fail "integrate must make dev the default branch"
grep -Fq '"ref":"refs/heads/dev","sha":"0123abc"' "$tmp/ref-body" ||
  fail "integrate must create dev at main"
grep -q '^5 .*--base dev' "$tmp/retargeted" || fail "integrate must retarget open PRs to dev"
[ -f "$tmp/release-post-body" ] || fail "integrate must protect the release branch"
rm "$tmp/ref-body"; bash "$script" integrate example/open >/dev/null 2>&1
[ ! -f "$tmp/ref-body" ] || fail "a second integrate must not recreate dev"
echo master > "$tmp/default-branch"
refuses "integrating a non-main default" "integrate expects default branch main or dev" \
  bash "$script" integrate example/open

# --- ensure integrates a brownfield repository unless it opts out ---------------
fresh "$good"
git init -q "$tmp/co"; git -C "$tmp/co" commit -q --allow-empty -m base
ensure() { (cd "$tmp/co" && bash "$script" ensure "$@"); }
out="$(ensure example/open 2>/dev/null)"
[ "$out" = "integration=dev release=main" ] || fail "ensure must integrate by default: $out"
out="$(ensure example/open 2>/dev/null)"
[ "$out" = "integration=dev release=main" ] || fail "ensure must be idempotent: $out"
fresh "$good"; printf 'Integration-branch: `main`\n' > "$tmp/co/AGENTS.md"
out="$(ensure example/open)"
[ "$out" = "integration=main release=none" ] && [ ! -f "$tmp/default-branch" ] ||
  fail "Integration-branch: main must opt out: $out"
printf 'Integration-branch: trunk\n' > "$tmp/co/AGENTS.md"
refuses "an unknown integration branch" "must be dev or main" ensure example/open
rm "$tmp/co/AGENTS.md"
out="$(ensure example/open-prd)"
[ "$out" = "integration=main release=none" ] && [ ! -f "$tmp/default-branch" ] ||
  fail "a -prd repository stays single-branch: $out"

echo "protect-main tests passed"
