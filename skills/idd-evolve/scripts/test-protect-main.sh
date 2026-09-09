#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/skills/idd-evolve/scripts/protect-main.sh"
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
case "$method $path" in
  "PATCH repos/"*) cat > "$root/patch-body"; cp "$root/patch-body" "$root/settings";;
  "POST repos/"*"/rulesets") cat > "$root/post-body"; echo 42 > "$root/ruleset-id"; cp "$root/post-body" "$root/ruleset";;
  "PUT repos/"*"/rulesets/"*) cat > "$root/put-body"; cp "$root/put-body" "$root/ruleset";;
  "GET repos/"*"/rulesets/"*) jq -r "$jq" "$root/ruleset";;
  "GET repos/"*"/rulesets") if [ -f "$root/ruleset-id" ]; then jq -n --argjson id "$(cat "$root/ruleset-id")" '[{name:"require-pull-request",id:$id}]'; else echo '[]'; fi | jq -r "$jq";;
  "GET repos/"*) if [ "$jq" = .visibility ]; then cat "$root/visibility"; else jq -r "$jq" "$root/settings"; fi;;
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

fresh() { rm -f "$tmp"/{calls,patch-body,post-body,put-body,ruleset-id,ruleset,refuse-writes,refuse-rulesets}; settings_fixture "$1"; echo public > "$tmp/visibility"; }
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "protect-main accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "protect-main rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
}

# --- verify fails closed on an unprotected repository -------------------------
fresh 'true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES'
refuses "an unprotected repository" "no ruleset named require-pull-request" bash "$script" verify example/open
refuses "drifted merge settings" "settings drift" bash "$script" verify example/open
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
# so both verify and apply must name the plan limit from that first refused call.
fresh 'true false false true PR_TITLE PR_BODY'; touch "$tmp/refuse-rulesets"; echo private > "$tmp/visibility"
refuses "a refused rulesets read on verify" "GitHub Free does not enforce rulesets on a private repository; make example/locked" bash "$script" verify example/locked
refuses "a refused rulesets read on apply" "GitHub Free does not enforce rulesets on a private repository; make example/locked" bash "$script" apply example/locked
[ ! -f "$tmp/post-body" ] && [ ! -f "$tmp/put-body" ] || { echo "a refused read must not be followed by a ruleset write" >&2; exit 1; }
rm -f "$tmp/refuse-rulesets"

# --- the repository defaults to the current checkout --------------------------
fresh 'true false false true PR_TITLE PR_BODY'; echo 7 > "$tmp/ruleset-id"; cp "$tmp/protected-ruleset" "$tmp/ruleset"
out="$(bash "$script" verify)"
case "$out" in "maximalfocus/current default branch protected"*) ;; *) echo "verify must default to the checkout repository: $out" >&2; exit 1;; esac

# --- usage ---------------------------------------------------------------------
refuses "an unknown mode" "usage:" bash "$script" enable example/open
refuses "a bare repository name" "usage:" bash "$script" verify open

echo "protect-main tests passed"
