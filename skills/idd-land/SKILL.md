---
name: idd-land
description: >-
  User-invoked landing of one completed IDD issue, or the gated landing phase of idd-auto:
  validate its PR, squash-merge, close, refresh, and delete its feature branch.
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd-land — explicitly land one completed issue

`/idd-implement` stops at an open PR; `/idd-land` is the separate destructive lifecycle step. An
explicit invocation (directly or through `/idd`, per Constitution Article 5), an active explicitly
invoked `/idd-auto` run for its one current accepted PR, or an explicit `/idd-publish` run for its
one accepted preparation PR authorizes squash merge, issue closure, default-branch refresh, deletion
of that PR's same-repository remote and local feature branch, and automatic progress reconciliation
in an exact convention-linked sibling `{project}-prd` repository when present — never force-push,
bypassing failed checks/reviews/conflicts, deployment, or landing any other issue.

Take one issue number/URL from the invocation or user request; optional `--pr N` resolves ambiguity.
`--accept-residuals` means the user knowingly accepts clearly disclosed unproved acceptance items;
it never overrides red/pending checks, requested changes, conflicts, draft state, repository
mismatch, or a dirty tree.

## Step 0 — resolve and fail closed

1. First run the sibling `idd-plan/scripts/protect-main.sh ensure` and print its `integration=…
   release=…` line; landing merges into the integration (default) branch and never promotes. Resolve
   repo root, `origin`, current branch, and status. Require a clean working tree and `gh auth
   status`; require the issue repository to match `gh repo view --json nameWithOwner`.
2. Read the live issue and comments. Allow `OPEN`; allow `CLOSED` only when resuming a partially
   completed landing whose linked PR is already merged.
3. Resolve PRs from the issue's cross-references and closing references: require exactly one
   same-repository PR unless `--pr N` was supplied, verify the chosen PR actually references the
   issue, and never guess between candidates.
4. Read the chosen PR's body, reviews, checks, merge state, draft state, base/head refs, and linked
   issue. Require `OPEN` or already `MERGED`, a same-repository head branch, the expected default
   base, no requested changes, `mergeable=MERGEABLE`, and every reported check completed
   successfully/skipped/neutral. A closed-unmerged PR stops.
5. Resolve the sibling `idd-plan` skill in the same installation root and run its bundled
   `scripts/resolve-prd-pair.sh`: exit 3 means no associated PRD and landing proceeds without
   reconciliation; a missing sibling is an incomplete installation and stops. With a pair, require
   the PRD checkout clean, correctly associated, and synced by `idd-plan/scripts/progress-pr.sh
   sync`; pre-resolve the issue's context from its label when `idd-plan/scripts/contract.sh list`
   names contexts, then its exact tracker row — in that context's `PROGRESS.md` plus its portfolio
   row — or an explicit no-applicable-row result. Ambiguity stops before GitHub mutation.

## Step 1 — acceptance and residual gate

Reconcile every issue checkbox/acceptance item against the PR body, verification evidence, and
current repository state. Search explicitly for `Refs`, remaining gates, skipped/not-run checks,
caveats, and residuals.

Confirm the completed change fits the product model before merge: established concepts, naming,
domain boundary, and public contracts stay coherent, and any novel concept, special case, boundary
move, or fragmenting convenience feature is an explicit design decision in the issue or PR — an
unrecorded departure is an unproved acceptance item, not a cheap fix to land. In a partitioned
contract the PR's changed files must resolve to the issue's context through
`idd-plan/scripts/contract.sh owner`, unless the issue records a cross-context design decision.

All acceptance proved: proceed. Any item unproved: stop, list it, and require a fresh explicit
`/idd-land … --accept-residuals` invocation. With `--accept-residuals`: restate the exact accepted
gaps, then proceed; never reinterpret the flag as proof or hide the gaps from the completion report.

## Delivery type and the landed subject

GitHub derives a squash subject from the pull-request title, which N-2 deliberately leaves untyped,
so the pull request declares the landed type in exactly one body field, `Delivery-Type: <type>`.
Landing composes `<type>: <issue title> (#<PR>)`, lowercasing the title's initial ASCII letter
unless an initialism opens it, and passes it to the squash merge. It stops rather than guessing when
the field is absent, repeated, or not an N-4 type, one vocabulary for every repository. The authored
part before the trailing ` (#N)` is capped at 72 characters and never truncated — an over-budget
subject is a title to shorten, not a rule to bend. Issue and PR titles stay untyped. Before any
mutation the script also enforces the rest of the sibling `idd-plan/references/conventions.md`: the
PR title equals the issue title (N-2), the head is `issue/<N>-<slug>` (N-3), `protect-main.sh
verify` passes, and the head adds no line over 100 characters outside `Formatter-owned:` paths and
Markdown table rows; repair the source, never the gate. Only the user's explicit instruction runs
`apply`, which changes repository settings: see the conventions' adoption section.

## GATE — pre-merge snapshot

Immediately before mutation, re-read PR state/checks and `git status`, confirm the issue number, PR
number, repository, base branch, and feature branch in chat, then run the deterministic script:

```sh
bash /absolute/path/to/installed/idd-land/scripts/land.sh OWNER/REPO ISSUE PR
```

Resolve the script from this installed skill directory, not the project checkout, and never
hand-reimplement its sequence; it runs as one function parsed whole before execution, so a checkout
that rewrites its source mid-landing cannot change the running sequence.

## Step 2 — verify the landed state

Require from the script, and independently read back: the PR `MERGED` with a squash merge commit;
the issue `CLOSED` after the merge; the local checkout on the updated default branch with a clean
tree; the same-repository remote and local feature refs absent; and, when this invocation performed
the merge, the composed landed subject. The script is resumable after a partial failure: an
already-merged PR skips merging and continues closure/cleanup without re-checking a subject it did
not write. Any failed postcondition is reported precisely and is never called complete.

## Step 3 — automatically reconcile associated PRD progress

When Step 0 found an associated PRD, first run the sibling `idd-plan/scripts/tracker-gate.sh` on the
owning `PROGRESS.md` — and `idd-plan/scripts/contract.sh gate` on the whole partitioned contract: a
stopped gate is `landed, PRD reconciliation incomplete` with the reported line and cell, repaired by
`/idd-plan --reconcile` folding the tracker under its own update rule, never a raised budget. Then
read the sibling `skills/idd-plan/SKILL.md` and execute its Reconcile mode with the verified issue,
PR, and squash commit; this is mandatory and requires no separate user invocation. When landed
behavior makes `PRD.md` prose inaccurate, report `landed, PRD text stale` naming the requirement,
repaired by the user's `docs(prd)` PR, never a reconcile edit. Verify the batch push and any
milestone merge — a merge refused for review state is `PRD batch awaiting review`, not a failed
landing — then return to the implementation checkout. A reconciliation failure after merge never
undoes or conceals the landing: it is `landed, PRD reconciliation incomplete`, resumable by this
invocation; without an associated PRD, report `PRD reconciliation: not configured`.

## Completion output

Return only the issue/PR URLs, squash commit, closure state, deleted branch names, current default
branch, accepted residuals (if any), PRD batch PR and commit/push/merge state, any stale-requirement
report, and any incomplete postcondition.
