#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${CONTRACT_SCRIPT:-$root/scripts/contract.sh}"
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"; trap 'rm -rf "$tmp"' EXIT

words() { # $1 = count; prints that many words on one line
  awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "w%d%s", i, (i < n ? " " : "\n") }'
}
tracker() { # $1 = title, $2 = file
  printf '# %s progress\n\n| Item | Status |\n|---|---|\n| Baseline | ready |\n\n## Update rule\n\nEdit on landing.\n' "$1" > "$2"
}
context_prd() { # $1 = file, $2 = title, $3 = scope bullets, $4 = depends bullets
  printf '# %s\n\n## Scope\n\n%s\n\n## Depends on\n\n%s\n\n## Requirements\n\nOne requirement.\n' "$2" "$3" "$4" > "$1"
}
index_prd() { # $1 = file, remaining = context rows
  local file="$1"; shift
  { printf '# demo product requirements\n\n## Product model\n\nOne product.\n\n## Contexts\n\n| Context | Owns | Depends on |\n|---|---|---|\n'
    printf '%s\n' "$@"
    printf '\n## Cross-context invariants\n\n- One invariant.\n\n## Gold standard\n\n### Preserved artifacts\n\nNone declared.\n'; } > "$file"
}
snapshot() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs cksum); }
refuses() { # $1 = description, $2 = required stderr fragment, remaining = command
  local desc="$1" want="$2" err; shift 2
  if err="$("$@" 2>&1 >/dev/null)"; then echo "contract accepted $desc" >&2; exit 1; fi
  case "$err" in *"$want"*) ;; *) echo "contract rejected $desc for the wrong reason: $err" >&2; exit 1;; esac
  case "$err" in *"FAIL: contract gate ("*) ;; *) echo "missing aggregate verdict for $desc: $err" >&2; exit 1;; esac
}
broken() { # $1 = case name; copies the multi-context fixture to a fresh directory and prints its path
  cp -R "$tmp/multi" "$tmp/$1"; printf '%s\n' "$tmp/$1"
}

# --- a single-context contract -----------------------------------------------
mkdir -p "$tmp/single"
printf '# demo product requirements\n\n## Requirements\n\nOne requirement.\n\n## Gold standard\n\n### Preserved artifacts\n\nNone declared.\n' > "$tmp/single/PRD.md"
tracker demo "$tmp/single/PROGRESS.md"
before="$(snapshot "$tmp/single")"
[ -z "$(bash "$script" list "$tmp/single")" ] || { echo "list reported contexts for a single-context contract" >&2; exit 1; }
bash "$script" gate "$tmp/single" | grep -q "^PASS: contract gate ($tmp/single)\$" || { echo "gate rejected a single-context contract" >&2; exit 1; }
out="$(bash "$script" owner "$tmp/single" src/a.java docs/readme.md)"
[ "$out" = "$(printf 'src/a.java\troot\ndocs/readme.md\troot')" ] || { printf 'wrong single-context owner output:\n%s\n' "$out" >&2; exit 1; }
[ "$before" = "$(snapshot "$tmp/single")" ] || { echo "contract tooling rewrote the single-context fixture" >&2; exit 1; }

# --- a multi-context contract ------------------------------------------------
mkdir -p "$tmp/multi/contexts/platform" "$tmp/multi/contexts/road-tax"
index_prd "$tmp/multi/PRD.md" '| `platform` | framework | None |' '| `road-tax` | road tax commands | `platform` |'
tracker portfolio "$tmp/multi/PROGRESS.md"
context_prd "$tmp/multi/contexts/platform/PRD.md" platform $'- `src/framework/*`\n- `src/shared/*`' '- None'
tracker platform "$tmp/multi/contexts/platform/PROGRESS.md"
context_prd "$tmp/multi/contexts/road-tax/PRD.md" 'road tax' $'- `src/app/*/rtx/*`\n- `src/shared/*` (shared models it extends)' '- `platform` for the command bus'
tracker 'road tax' "$tmp/multi/contexts/road-tax/PROGRESS.md"
before="$(snapshot "$tmp/multi")"
[ "$(bash "$script" list "$tmp/multi")" = "$(printf 'platform\nroad-tax')" ] || { echo "list did not print both contexts" >&2; exit 1; }
bash "$script" gate "$tmp/multi" | grep -q "^PASS: contract gate ($tmp/multi)\$" || { echo "gate rejected a valid multi-context contract" >&2; exit 1; }
out="$(bash "$script" owner "$tmp/multi" src/app/command/rtx/Foo.java src/framework/x.java docs/readme.md src/shared/Model.java)"
expected="$(printf 'src/app/command/rtx/Foo.java\troad-tax\nsrc/framework/x.java\tplatform\ndocs/readme.md\tnone\nsrc/shared/Model.java\tambiguous:platform,road-tax')"
[ "$out" = "$expected" ] || { printf 'wrong multi-context owner output:\n%s\n' "$out" >&2; exit 1; }
[ "$before" = "$(snapshot "$tmp/multi")" ] || { echo "contract tooling rewrote the multi-context fixture" >&2; exit 1; }

# --- each structural failure, on its own copy --------------------------------
dir="$(broken half)"; rm "$dir/contexts/road-tax/PROGRESS.md"
refuses "a context without a tracker" "FAIL: context road-tax lacks PRD.md or PROGRESS.md" bash "$script" gate "$dir"
bash "$script" list "$dir" >/dev/null 2>&1 && { echo "list accepted a context without a tracker" >&2; exit 1; }

dir="$(broken ghost)"; index_prd "$dir/PRD.md" '| `platform` | framework | None |' '| `road-tax` | road tax commands | `platform` |' '| `billing` | invoices | None |'
refuses "an index row without a directory" "FAIL: index lists context billing without a directory" bash "$script" gate "$dir"

dir="$(broken orphan)"; index_prd "$dir/PRD.md" '| `platform` | framework | None |'
refuses "a directory without an index row" "FAIL: context road-tax has no row in the index Contexts table" bash "$script" gate "$dir"

dir="$(broken scopeless)"; context_prd "$dir/contexts/road-tax/PRD.md" 'road tax' '- everything under the rtx packages' '- `platform`'
refuses "a context with no scope bullets" "FAIL: context road-tax declares no scope" bash "$script" gate "$dir"

dir="$(broken unknown)"; context_prd "$dir/contexts/road-tax/PRD.md" 'road tax' '- `src/app/*/rtx/*`' '- `billing`'
refuses "a dependency on an unknown context" "FAIL: context road-tax depends on unknown context billing" bash "$script" gate "$dir"

dir="$(broken selfish)"; context_prd "$dir/contexts/road-tax/PRD.md" 'road tax' '- `src/app/*/rtx/*`' '- `road-tax`'
refuses "a self-dependency" "FAIL: context road-tax depends on itself" bash "$script" gate "$dir"

dir="$(broken nodeps)"; printf '# road tax\n\n## Scope\n\n- `src/app/*/rtx/*`\n\n## Requirements\n\nOne.\n' > "$dir/contexts/road-tax/PRD.md"
refuses "a context without a dependencies section" "FAIL: context road-tax declares no dependencies section" bash "$script" gate "$dir"

dir="$(broken oversized)"; { printf '\n## Big\n\n'; words 1001; } >> "$dir/contexts/road-tax/PRD.md"
before="$(snapshot "$dir")"
refuses "an over-budget context PRD" "section 'Big' 1001 words, budget 1000" bash "$script" gate "$dir"
[ "$before" = "$(snapshot "$dir")" ] || { echo "contract gate rewrote an over-budget context" >&2; exit 1; }

# --- argument errors ---------------------------------------------------------
status=0; bash "$script" gate "$tmp/absent" 2>/dev/null || status=$?
[ "$status" -eq 2 ] || { echo "a missing contract must exit 2, got $status" >&2; exit 1; }
status=0; bash "$script" owner "$tmp/multi" 2>/dev/null || status=$?
[ "$status" -eq 64 ] || { echo "owner without paths must exit 64, got $status" >&2; exit 1; }
status=0; bash "$script" bogus "$tmp/multi" 2>/dev/null || status=$?
[ "$status" -eq 64 ] || { echo "an unknown subcommand must exit 64, got $status" >&2; exit 1; }
echo "contract tooling valid"
