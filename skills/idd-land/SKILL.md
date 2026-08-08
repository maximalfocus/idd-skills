---
name: idd-land
description: "Land one completed IDD issue: validate its linked PR and acceptance state, squash-merge, close the issue, update the default branch, and delete the remote/local feature branch. Use only when the user explicitly invokes /idd-land for an issue."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
disable-model-invocation: true
argument-hint: "[issue-number|github-issue-url] [--pr N] [--accept-residuals]"
---

# /idd-land — explicitly land one completed issue

`/idd` stops at an open PR; `/idd-land` is the separate destructive lifecycle step. An explicit invocation authorizes squash merge, issue closure, default-branch refresh, deletion of that PR's same-repository remote/local feature branch, and automatic progress reconciliation in an exact convention-linked sibling `{project}-prd` repository when present. It does not authorize force-push, bypassing failed checks/reviews/conflicts, deployment, or landing any other issue.

## Input and authority

Take one issue number/URL from the invocation or user request. Optional `--pr N` resolves ambiguity. `--accept-residuals` means the user knowingly accepts clearly disclosed unproved acceptance items; it never overrides red/pending checks, requested changes, conflicts, draft state, repository mismatch, or a dirty tree.

## Step 0 — resolve and fail closed

1. Resolve repo root, `origin`, default branch, current branch, and status. Require a clean working tree and `gh auth status`; require the issue repository to match `gh repo view --json nameWithOwner`.
2. Read the live issue and comments. Allow `OPEN`; allow `CLOSED` only when resuming a partially completed landing whose linked PR is already merged.
3. Resolve PRs from the issue's cross-references and closing references. Require exactly one same-repository PR unless `--pr N` was supplied, and verify the chosen PR actually references the issue. Never guess between multiple candidates.
4. Read the chosen PR's body, reviews, checks, merge state, draft state, base/head refs, and linked issue. Require `OPEN` or already `MERGED`, same-repository head branch, expected default base, no requested changes, `mergeable=MERGEABLE`, and every reported check completed successfully/skipped/neutral. A closed-unmerged PR stops.
5. Resolve this skill's physical source repository and run `scripts/resolve-prd-pair.sh`. Exit 3 means no associated PRD and landing proceeds without reconciliation. When a pair is found, require the PRD checkout to be clean, on its default branch, correctly associated, and able to fast-forward; pre-resolve the issue's exact tracker row or an explicit no-applicable-row result. Ambiguity stops before GitHub mutation.

## Step 1 — acceptance and residual gate

Reconcile every issue checkbox/acceptance item against the PR body, verification evidence, and current repository state. Search explicitly for `Refs`, remaining gates, skipped/not-run checks, caveats, and residuals.

- All acceptance proved: proceed.
- Any item unproved: stop, list it, and require a fresh explicit `/idd-land … --accept-residuals` invocation.
- With `--accept-residuals`: restate the exact accepted gaps, then proceed. Never reinterpret the flag as proof or hide the gaps from the completion report.

## GATE — pre-merge snapshot

Immediately before mutation, re-read PR state/checks and `git status`. Confirm the issue number, PR number, repository, base branch, and feature branch in chat. Then invoke the deterministic landing script:

```sh
bash /absolute/path/to/idd-skills/scripts/land.sh OWNER/REPO ISSUE PR
```

Resolve the script from this skill's physical source repository, not from the project checkout. Do not hand-reimplement its sequence.

## Step 2 — verify the landed state

Require all of the following from the script and independently read them back:

- PR is `MERGED` with a squash merge commit;
- issue is `CLOSED` after the merge;
- local checkout is the updated default branch with a clean tree;
- same-repository remote feature ref is absent;
- local feature ref is absent.

The script is resumable after a partial failure: an already-merged PR skips merging and continues closure/cleanup. Any failed postcondition is reported precisely and is never called complete.

## Step 3 — automatically reconcile associated PRD progress

When Step 0 found an associated PRD, read the physical sibling `skills/idd-plan/SKILL.md` and execute its Reconcile mode with the verified issue, PR, and squash commit. This is mandatory and requires no separate user invocation. Verify the PRD commit and push, then return to the implementation checkout. If reconciliation fails after merge, do not undo or conceal the landing: report `landed, PRD reconciliation incomplete` and make the same `/idd-land` invocation resumable. If no associated PRD exists, report `PRD reconciliation: not configured`.

## Completion output

Return only the issue/PR URLs, squash commit, closure state, deleted branch names, current default branch, accepted residuals (if any), PRD reconciliation path/commit/push state, and any incomplete postcondition.
