---
name: idd-land
description: "User-invoked landing of one completed IDD issue, or the gated landing phase of idd-auto: validate its PR, squash-merge, close, refresh, and delete its feature branch."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd-land — explicitly land one completed issue

`/idd` stops at an open PR; `/idd-land` is the separate destructive lifecycle step. A direct explicit invocation, or an active explicitly invoked `/idd-auto` run for its one current accepted PR, authorizes squash merge, issue closure, default-branch refresh, deletion of that PR's same-repository remote/local feature branch, and automatic progress reconciliation in an exact convention-linked sibling `{project}-prd` repository when present. It does not authorize force-push, bypassing failed checks/reviews/conflicts, deployment, or landing any other issue.

## Input and authority

Take one issue number/URL from the invocation or user request. Optional `--pr N` resolves ambiguity. `--accept-residuals` means the user knowingly accepts clearly disclosed unproved acceptance items; it never overrides red/pending checks, requested changes, conflicts, draft state, repository mismatch, or a dirty tree.

## Step 0 — resolve and fail closed

1. Resolve repo root, `origin`, default branch, current branch, and status. Require a clean working tree and `gh auth status`; require the issue repository to match `gh repo view --json nameWithOwner`.
2. Read the live issue and comments. Allow `OPEN`; allow `CLOSED` only when resuming a partially completed landing whose linked PR is already merged.
3. Resolve PRs from the issue's cross-references and closing references. Require exactly one same-repository PR unless `--pr N` was supplied, and verify the chosen PR actually references the issue. Never guess between multiple candidates.
4. Read the chosen PR's body, reviews, checks, merge state, draft state, base/head refs, and linked issue. Require `OPEN` or already `MERGED`, same-repository head branch, expected default base, no requested changes, `mergeable=MERGEABLE`, and every reported check completed successfully/skipped/neutral. A closed-unmerged PR stops.
5. Resolve the sibling `idd-plan` skill in the same installation root and run its bundled `scripts/resolve-prd-pair.sh`. Exit 3 means no associated PRD and landing proceeds without reconciliation. A missing sibling is an incomplete installation and stops. When a pair is found, require the PRD checkout to be clean, on its default branch, correctly associated, and able to fast-forward; pre-resolve the issue's exact tracker row or an explicit no-applicable-row result. Ambiguity stops before GitHub mutation.

## Step 1 — acceptance and residual gate

Reconcile every issue checkbox/acceptance item against the PR body, verification evidence, and current repository state. Search explicitly for `Refs`, remaining gates, skipped/not-run checks, caveats, and residuals.

Confirm the completed change fits the product model before merge: established concepts, naming, domain boundary, and public contracts remain coherent; any novel concept, special case, boundary move, or fragmenting convenience feature is an explicit design decision in the issue or PR. An unrecorded departure is an unproved acceptance item, not a cheap fix to land.

- All acceptance proved: proceed.
- Any item unproved: stop, list it, and require a fresh explicit `/idd-land … --accept-residuals` invocation.
- With `--accept-residuals`: restate the exact accepted gaps, then proceed. Never reinterpret the flag as proof or hide the gaps from the completion report.

## Delivery type and the landed subject

GitHub derives a squash subject from the pull-request title, which the title conventions deliberately leave untyped, so the landed commit's type is otherwise the provider's choice. The pull request declares it instead, in exactly one body field:

```
Delivery-Type: <type>
```

Landing composes `<type>: <issue title with its initial ASCII letter lowercased> (#<PR>)` and passes it to the squash merge. It stops rather than guessing when the field is absent, declared more than once, not a lowercase type token, or not in the type vocabulary the repository declares in its own `AGENTS.md`/`CLAUDE.md` (`Types:` line); a repository that declares none is not constrained to any list. The authored portion, excluding the trailing ` (#N)`, is capped at 72 characters and is never truncated — an over-budget subject is a title to shorten, not a rule to bend. Issue and pull-request titles stay untyped.

## GATE — pre-merge snapshot

Immediately before mutation, re-read PR state/checks and `git status`. Confirm the issue number, PR number, repository, base branch, and feature branch in chat. Then invoke the deterministic landing script:

```sh
bash /absolute/path/to/installed/idd-land/scripts/land.sh OWNER/REPO ISSUE PR
```

Resolve the script from this installed skill directory, not from the project checkout. Do not hand-reimplement its sequence. The script runs as one function parsed whole before execution, so a checkout that rewrites its source mid-landing cannot change the running sequence.

## Step 2 — verify the landed state

Require all of the following from the script and independently read them back:

- PR is `MERGED` with a squash merge commit;
- issue is `CLOSED` after the merge;
- local checkout is the updated default branch with a clean tree;
- same-repository remote feature ref is absent;
- local feature ref is absent;
- the landed subject is the composed one, when this invocation performed the merge.

The script is resumable after a partial failure: an already-merged PR skips merging and continues closure/cleanup, and does not re-check a subject it did not write. Any failed postcondition is reported precisely and is never called complete.

## Step 3 — automatically reconcile associated PRD progress

When Step 0 found an associated PRD, run the sibling `idd-plan/scripts/tracker-gate.sh` on its `PROGRESS.md` first: a stopped gate is `landed, PRD reconciliation incomplete` with the reported line and cell; the repair is `/idd-plan --reconcile` folding the tracker under its own update rule, never a raised budget. Then read the physical sibling `skills/idd-plan/SKILL.md` and execute its Reconcile mode with the verified issue, PR, and squash commit. This is mandatory and requires no separate user invocation. When the landed change makes requirement prose in `PRD.md` inaccurate, report `landed, PRD text stale` naming the requirement; the repair is a `prd` commit by the user, never a reconcile edit. Verify the PRD commit and push, then return to the implementation checkout. If reconciliation fails after merge, do not undo or conceal the landing: report `landed, PRD reconciliation incomplete` and make the same `/idd-land` invocation resumable. If no associated PRD exists, report `PRD reconciliation: not configured`.

## Completion output

Return only the issue/PR URLs, squash commit, closure state, deleted branch names, current default branch, accepted residuals (if any), PRD reconciliation path/commit/push state, any stale-requirement report, and any incomplete postcondition.
