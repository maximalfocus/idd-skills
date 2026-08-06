---
name: idd
description: "Issue-Driven Development for an existing software repository: take one well-scoped GitHub issue from live issue intent through a focused implementation, repository-native tests, commit, push, and linked PR. Use when the user says /idd, asks to implement/fix issue N, or provides a GitHub issue URL and wants a lightweight alternative to CDD."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
disable-model-invocation: true
argument-hint: "[issue-number|github-issue-url]"
---

# /idd — implement one issue, without the CDD artifact pipeline

Deliver one independently reviewable GitHub issue in its existing repository. The live issue is the acceptance source; the repository's own instructions, architecture, tests, and PR policy are the implementation system. Do not create PRDs, golden suites, sibling repos, methodology traces, or mandatory peer-review rounds.

An explicit `/idd` invocation authorizes a dedicated branch, commits, push, and a linked PR. It never authorizes merge, deployment, issue closure by hand, force-push, destructive git operations, or edits outside the issue's repository.

## Input

Take one issue number (`issue 6`, `#6`, or `6`) or GitHub issue URL from the invocation arguments or, on runners that do not inject arguments into skills, from the user's request. Default repository: the current git repository. One run handles one issue.

## Step 0 — establish a safe issue boundary

1. Resolve repo root, default branch, remotes, current branch, and status. Read root `AGENTS.md`/`CLAUDE.md` plus the relevant instructions they reference. Never overwrite or stage unrelated work.
2. Fetch the issue with body **and comments** (`gh issue view … --json number,title,body,comments,labels,state,url`); require `OPEN` and require its repository to match the checkout's remote (otherwise ask for the correct local checkout). Comments are intent only when authoritative and non-conflicting. Record the canonical issue URL.
3. Reject or ask to split an epic that cannot be reviewed and verified as one coherent change. For a bug, locate the reproduction; for a feature/change, locate the affected user or system boundary.
4. If the working tree is dirty, do not discard or absorb it. Ask whether it is a prerequisite; otherwise create a sibling worktree from the current committed base. If clean, create `issue/<number>-<short-slug>` before the first write. Never implement on the default/shared branch.
5. Confirm GitHub auth and that push access or the repository's fork workflow is available. A tooling failure is a disclosed blocker, not a reason to bypass policy.

## Step 1 — turn live intent into a small execution contract

In chat, summarize:

- required outcome and explicit acceptance criteria;
- chosen path when the issue offers alternatives (follow an explicit recommendation; ask when no preference is authoritative);
- non-goals and likely files/boundaries;
- verification commands or observable checks.

Inspect code and discoverable facts before asking questions. Ask only when conflicting or missing intent would materially change behavior, security, data, API shape, or scope. Do not ask for implementation choices the repository already answers. The checklist is working context, not a new tracked planning artifact.

## Step 2 — inspect narrowly, then implement

1. Trace the affected path end-to-end before editing: entry point → logic/config → dependency boundary → user-visible or operational result. Search every entry point named by the issue; “hide/disable all” requires an exhaustive search, not one obvious button.
2. Follow existing patterns and keep the smallest coherent diff. Preserve public contracts unless the issue changes them. Update repository documentation only where it is a maintained source of truth or the issue requires a recorded decision.
3. Add tests at the acceptance boundary. Prefer a regression test for a bug and focused behavior tests for a feature. Do not rewrite tests to bless incorrect behavior or broaden into unrelated cleanup.
4. Treat security, auth, secrets, migrations, runtime flags, and destructive operations as high-risk. Fail closed where the issue requires it; never commit credentials or weaken safeguards to make a test pass.
5. Keep scope honest. If implementation reveals a distinct follow-up, leave it out and report it; do not silently turn one issue into a refactor campaign.

## Step 3 — verify in risk order

Run the cheapest relevant checks first, then the repository's prescribed gate:

1. changed-area unit/regression tests;
2. compile/typecheck/lint for affected units;
3. integration or repository-wide tests required by repo instructions;
4. the **actual changed boundary**: build/run the container, CLI, migration, runtime config, HTTP route, or browser flow when unit tests cannot prove deployment behavior.

A green unit suite does not prove container startup, generated runtime files, routing, profile/bean selection, migration validity, or browser deep links. Exercise those directly when changed. For a runtime flag, verify its default, valid override, invalid value, profile/config precedence, and the baked artifact when startup hooks can be bypassed; an unsupported deployment profile must not be overrideable into an incomplete feature.

If a broad gate is red, classify it before proceeding:

- **Introduced by this branch** → fix it.
- **Pre-existing baseline** → prove it using documented repo evidence or the same command at the base commit in a clean worktree; run the issue-specific slice green and disclose the exact baseline failure.
- **Environment/tooling** → repair safely when local-only, otherwise disclose the concrete blocker.

Never call the repository fully green when a gate is red. A proven unrelated baseline failure may be disclosed in the PR; a required branch check that will block merge remains a blocker.

## GATE — issue acceptance and diff audit

Before delivery:

- map every issue acceptance item to a code change, test, or explicit evidence;
- inspect `git diff --check`, `git diff`, and `git status`;
- verify no unrelated files, generated junk, secrets, debug code, or accidental lockfile changes;
- rerun the load-bearing issue checks after the final edit;
- when retiring a stub, flag, or profile restriction, exhaustively search source and maintained docs for superseded status markers; qualify same-named components across stacks.

If any acceptance item is ambiguous or unproved, stop claiming completion and say so; a reviewable implementation may still open a non-closing PR.

## Step 4 — commit and open the PR

1. Stage only issue-owned paths explicitly. Commit with the repository's message convention and a concise issue-focused subject.
2. Push the dedicated branch. Open a focused PR using the repository template. Include summary, verification commands/results, proven baseline failures, and risks/follow-ups. Use `Closes #N` only when every acceptance item is proved and the issue belongs to this repository; otherwise use a non-closing `Refs #N` (same repo) or `Refs owner/repo#N`.
3. Read back the PR URL and state. Do not merge it, delete the branch, deploy, or close the issue directly. Merge policy and CI remain the repository's gate.

## Completion output

Return only:

- issue and chosen outcome;
- key implementation points;
- verification (green checks plus precisely named baseline/tooling limitations);
- commit, PR URL, and current lifecycle state;
- exactly one next action (`/idd-land #N` when the PR is ready, otherwise the named blocker);
- excluded follow-ups, if any.

A paused run stays on its issue branch. Resume by re-reading the live issue, branch diff, and PR state; never rely on a separate trace file.
