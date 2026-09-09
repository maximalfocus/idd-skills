#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/skills/idd-evolve/scripts/protect-main.sh"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT
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
if [ "$method" != GET ] && [ -f "$root/refuse-writes" ]; then
  echo "gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)" >&2; exit 1
fi
case "$method $path" in
  "PATCH repos/"*) cat > "$root/patch-body"; printf 'true false false true PR_TITLE PR_BODY' > "$root/settings";;
  "POST repos/"*"/rulesets") cat > "$root/post-body"; echo 42 > "$root/ruleset-id"; cp "$root/protected-ruleset" "$root/ruleset";;
  "PUT repos/"*"/rulesets/"*) cat > "$root/put-body"; cp "$root/protected-ruleset" "$root/ruleset";;
  "GET repos/"*"/rulesets/"*) cat "$root/ruleset";;
  "GET repos/"*"/rulesets") [ -f "$root/ruleset-id" ] && cat "$root/ruleset-id" || true;;
  "GET repos/"*) if [ "$jq" = .visibility ]; then cat "$root/visibility"; else cat "$root/settings"; fi;;
  *) echo "unexpected gh api: $method $path" >&2; exit 2;;
esac
FAKE
chmod +x "$tmp/bin/gh"
printf 'active | 0 | ~DEFAULT_BRANCH | deletion,non_fast_forward,pull_request,required_linear_history | 0 true true squash' > "$tmp/protected-ruleset"

fresh() { rm -f "$tmp"/{calls,patch-body,post-body,put-body,ruleset-id,ruleset,refuse-writes}; printf '%s' "$1" > "$tmp/settings"; echo public > "$tmp/visibility"; }
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
printf 'active | 1 | ~DEFAULT_BRANCH | deletion,non_fast_forward,pull_request,required_linear_history | 0 true true squash' > "$tmp/ruleset"
refuses "a bypass actor" "ruleset drift" bash "$script" verify example/open
printf 'disabled | 0 | ~DEFAULT_BRANCH | deletion,non_fast_forward,pull_request,required_linear_history | 0 true true squash' > "$tmp/ruleset"
refuses "a disabled ruleset" "ruleset drift" bash "$script" verify example/open
printf 'active | 0 | ~DEFAULT_BRANCH | pull_request | 0 true true squash+merge' > "$tmp/ruleset"
refuses "missing rules and extra merge methods" "ruleset drift" bash "$script" verify example/open
cp "$tmp/protected-ruleset" "$tmp/ruleset"
printf 'true true false true PR_TITLE PR_BODY' > "$tmp/settings"
refuses "merge commits re-enabled" "settings drift" bash "$script" verify example/open

# --- a private repository on GitHub Free names the plan limit ------------------
fresh 'true true true false COMMIT_OR_PR_TITLE COMMIT_MESSAGES'; touch "$tmp/refuse-writes"; echo private > "$tmp/visibility"
refuses "a refused write on a private repository" "GitHub Free does not enforce rulesets on a private repository; make example/locked public" bash "$script" apply example/locked
echo public > "$tmp/visibility"
refuses "a refused write on a public repository" "HTTP 403" bash "$script" apply example/locked
err="$(bash "$script" apply example/locked 2>&1 >/dev/null || true)"
case "$err" in *"GitHub Free"*) echo "a public repository must not be told about the private plan limit" >&2; exit 1;; esac
rm -f "$tmp/refuse-writes"

# --- the repository defaults to the current checkout --------------------------
fresh 'true false false true PR_TITLE PR_BODY'; echo 7 > "$tmp/ruleset-id"; cp "$tmp/protected-ruleset" "$tmp/ruleset"
out="$(bash "$script" verify)"
case "$out" in "maximalfocus/current default branch protected"*) ;; *) echo "verify must default to the checkout repository: $out" >&2; exit 1;; esac

# --- usage ---------------------------------------------------------------------
refuses "an unknown mode" "usage:" bash "$script" enable example/open
refuses "a bare repository name" "usage:" bash "$script" verify open

echo "protect-main tests passed"
