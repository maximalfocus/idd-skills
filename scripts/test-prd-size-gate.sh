#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="${PRD_SIZE_GATE_SCRIPT:-$root/scripts/prd-size-gate.sh}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

words() { # $1 = count; prints that many words on one line
  awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) printf "w%d%s", i, (i < n ? " " : "\n") }'
}

# A small contract passes and the gate reports on stdout.
{ printf 'preamble\n\n# demo\n\n## Requirements\n\n### R-001 — One\n\n'; words 300; printf '\n## Non-goals\n\n'; words 50; } > "$tmp/PRD.md"
bash "$gate" "$tmp/PRD.md" | grep -q "^PASS: prd size gate ($tmp/PRD.md)\$" || { echo "size gate rejected a small PRD" >&2; exit 1; }

# One section over budget is named by line, heading, words and budget; the file is untouched.
{ printf '# demo\n\n## Requirements\n\n### R-001 — One\n\n'; words 400; printf '\n### R-002 — Two\n\n'; words 600; printf '\n'; words 401; printf '\n## Non-goals\n\n'; words 20; } > "$tmp/PRD.md"
before="$(cksum < "$tmp/PRD.md")"
if err="$(bash "$gate" "$tmp/PRD.md" 2>&1 >/dev/null)"; then echo "size gate accepted an over-budget section" >&2; exit 1; fi
case "$err" in *"line 9: section 'R-002 — Two' 1001 words, budget 1000"*) ;; *) echo "wrong section report: $err" >&2; exit 1;; esac
case "$err" in *"R-001"*) echo "size gate reported a section within budget" >&2; exit 1;; esac
case "$err" in *"contract:"*) echo "size gate reported a total within budget" >&2; exit 1;; esac
case "$err" in *"FAIL: prd size gate ($tmp/PRD.md): fold validated slices into their requirements"*) ;; *) echo "missing repair line: $err" >&2; exit 1;; esac
[ "$before" = "$(cksum < "$tmp/PRD.md")" ] || { echo "size gate rewrote the PRD" >&2; exit 1; }

# A whole contract over budget is reported even when every section fits.
{ printf 'intro words here\n\n# demo\n'; for i in $(seq 1 11); do printf '\n## Section %d\n\n' "$i"; words 950; done; } > "$tmp/PRD.md"
if err="$(bash "$gate" "$tmp/PRD.md" 2>&1 >/dev/null)"; then echo "size gate accepted an over-budget contract" >&2; exit 1; fi
case "$err" in *"contract: 10453 words, budget 10000"*) ;; *) echo "wrong contract report: $err" >&2; exit 1;; esac
case "$err" in *"line "*) echo "size gate reported a section within budget: $err" >&2; exit 1;; esac

bash "$gate" "$tmp/absent.md" 2>/dev/null && { echo "size gate accepted a missing PRD" >&2; exit 1; }
bash "$gate" 2>/dev/null && { echo "size gate accepted no arguments" >&2; exit 1; }
echo "prd size gate valid"
