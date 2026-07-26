---
name: idd-evolve
description: "IDD methodology evolution — filter lessons from real issue implementations through the constitution: pass → edit and publish; fail → do nothing. No logs."
disable-model-invocation: true
argument-hint: "[post-issue|simplify]"
---

# /idd-evolve — evolve Issue-Driven Development

Improve the IDD methodology from real use without growing `/idd` into CDD. A candidate either passes the constitution and lands, or leaves no trace; git history is the record.

## First: read the constitution

Read [`../../CONSTITUTION.md`](../../CONSTITUTION.md), then the skill files and their history (`git log --oneline -- skills/<name>/SKILL.md`) before changing anything. The constitution governs scope, evidence, size, deterministic scripting, and publication.

## Step 0 — reconstruct evidence

For **post-issue**, inspect primary evidence: the live issue and comments, project branch/PR diff and commits, verification output, review corrections, and relevant raw session traces under `~/.claude/projects/`. Match proof to the claim: one reproducible mechanical escape can establish a validation gap; behavioral advice normally needs multiple independent runs.

For **simplify**, measure skill sizes and find duplicated, unused, or tool-specific guidance. Prefer merge, replacement, compression, or deletion.

## GATE — pass or nothing

For each candidate:

1. Apply every constitution article. Reject anything speculative, already covered, project-specific, or incompatible with IDD's lightweight boundary; record nothing.
2. Make the smallest edit that fixes the proven gap, replacing existing prose where possible. Put mechanically deterministic behavior in `scripts/`, not prose.
3. Run `bash scripts/validate.sh`; verify references, diff, and size caps. Revert a candidate that fails or adds more complexity than capability.
4. Pull/rebase `origin/main`, stage only explicit changed paths, commit with a meaningful `evolve:` or `fix:` message, and push `main`. Never force-push.

## Completion

Report the evidence, kept change and why it passed, validation result, commit SHA, and push status. Rejected candidates produce no artifact. If this run exposes a defect in the evolve gate itself, fix it through the same constitution; otherwise do nothing.
