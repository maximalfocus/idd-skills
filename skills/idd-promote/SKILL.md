---
name: idd-promote
description: >-
  User-invoked, optional promotion of an IDD implementation repository's integration branch into
  its release branch: one reviewed dev-to-main pull request, merged with a merge commit.
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd-promote — promote the integration branch to the release branch

An implementation repository integrates on `dev`, its GitHub default branch: every issue PR targets
it and `/idd-land` squash-merges there. `main` is the release branch and changes only here. An
explicit invocation (directly or through `/idd`, per Constitution Article 5) authorizes opening, and
unless the request asks only to open it, merging one `dev`→`main` pull request. Nothing else ever
promotes: not `/idd-land`, `/idd-auto`, `/idd-acceptance`, or `/idd-publish`, and never inference.

Take an optional repository (`OWNER/REPO`) from the invocation or the user's request; default: the
current checkout. `--open-only` opens the PR for review and stops; a rerun resumes it.

## Orient

1. Resolve this installed skill directory and the sibling `idd-plan` skill; a missing sibling stops.
2. Run `idd-plan/scripts/protect-main.sh show` and print its `integration=… release=…` line first,
   so the user sees which branch is which before anything changes. `release=none` means the
   repository opted out with `Integration-branch: main` or was never integrated: stop and say so.
3. Read root `AGENTS.md`/`CLAUDE.md`. A project's own release policy (required approvals, a release
   checklist, a freeze window) governs whether to merge now; when it demands review first, use
   `--open-only`.

## Promote

Run the bundled `scripts/promote.sh [--open-only] [OWNER/REPO]`. It verifies both branches'
protection, reports `NOTHING to promote` when `main` already contains `dev`, and otherwise opens or
reuses the one open `dev`→`main` PR titled `chore(release): promote dev to main` (N-2 for an
issue-less PR) whose body lists the promoted commit subjects. It merges only a non-draft PR in
`CLEAN` merge state without requested changes, as a merge commit bound to the reviewed head, with
subject `<title> (#<PR>)`, then verifies the commit's second parent is that head.

## GATE — explicit, reviewed, never rewritten

- Never push to `main` or `dev` directly, force-push, squash or rebase the promotion (either makes
  `main` diverge from `dev`), delete `dev`, or bypass a `BLOCKED` state: resolve its reviews and
  threads, then rerun.
- A landing on `dev` after the PR opened is not promoted by it; the next promotion carries it.
- Promotion is not deployment or publication: it changes no repository visibility and deploys
  nothing.

## Completion output

Return the `integration=… release=…` line, the PR URL, and either `OPENED` (awaiting review),
`NOTHING to promote`, or `PROMOTED` with the merge commit and subject; name any stopped gate.
