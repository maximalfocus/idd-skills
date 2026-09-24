---
name: idd-implement
description: >-
  Issue-Driven Development for an existing software repository: take one well-scoped GitHub issue
  from live issue intent through a focused implementation, repository-native tests, commit, push,
  and linked PR. Use when the user says /idd-implement, /idd routes an issue number or URL here,
  or the user asks to implement/fix issue N and wants a lightweight alternative to CDD.
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd-implement — implement one issue, without the CDD artifact pipeline

Deliver one independently reviewable GitHub issue in its existing repository. The live issue is the
acceptance source; the repository's own instructions, architecture, tests, and PR policy are the
implementation system. No PRDs, golden suites, sibling repos, traces, or mandatory review rounds.

An explicit `/idd-implement` invocation, or an `/idd` request naming the issue to implement,
authorizes a dedicated branch, commits, push, and a linked PR; an active explicit `/idd-auto` run
supplies the same for its one current issue. Neither authorizes merging outside `/idd-land`,
deployment, closing the issue by hand, force-push, destructive git operations, or edits outside the
issue's repository.

## Input

Take one issue number (`issue 6`, `#6`, `6`) or GitHub issue URL from the arguments or, on runners
that inject none, the user's request. Default repository: the current one. One run, one issue.

## Step 0 — establish a safe issue boundary

1. First run the sibling `idd-plan/scripts/protect-main.sh ensure` and print its `integration=…
   release=…` line: the integration branch (`dev` unless opted out) is the default branch every PR
   targets. Resolve repo root, remotes, current branch, and status. Read root `AGENTS.md`/
   `CLAUDE.md` plus the instructions they reference. Never overwrite or stage unrelated work.
2. Fetch the issue with body **and comments** (`gh issue view … --json
   number,title,body,comments,labels,state,url`); require `OPEN` and require its repository to match
   the checkout's remote (otherwise ask for the correct local checkout). Comments are intent only
   when authoritative and non-conflicting. Record the canonical issue URL. When the checkout has an
   exact `{project}-prd` sibling whose `idd-plan/scripts/contract.sh list` names contexts, the
   issue's context label names the scope this change may touch.
3. Reject or ask to split an epic that cannot be reviewed and verified as one coherent change. For a
   bug, locate the reproduction; for a feature/change, locate the affected user or system boundary.
4. If the working tree is dirty, do not discard or absorb it. Ask whether it is a prerequisite;
   otherwise create a sibling worktree from the current committed base. If clean, create the N-3
   branch `issue/<number>-<slug>` before the first write. Never implement on the default branch.
5. Confirm GitHub auth and that push access or the repository's fork workflow is available. A
   tooling failure is a disclosed blocker, not a reason to bypass policy.

## Step 1 — turn live intent into a small execution contract

In chat, summarize the required outcome and explicit acceptance criteria; the chosen path when the
issue offers alternatives (follow an explicit recommendation; ask when no preference is
authoritative); non-goals and likely files/boundaries; and verification commands or observable
checks.

Inspect code and discoverable facts before asking. Ask only when conflicting or missing intent would
materially change behavior, security, data, API shape, or scope, never for choices the repository
already answers. The checklist is working context, not a tracked planning artifact.

## Step 2 — inspect narrowly, then implement

1. Trace the affected path end-to-end before editing: entry point → logic/config → dependency
   boundary → user-visible or operational result. Search every entry point named by the issue;
   “hide/disable all” requires an exhaustive search, not one obvious button.
2. Preserve the conceptual model over the cheapest change: follow existing patterns with the
   smallest coherent diff that keeps them and public contracts whole (unless the issue changes a
   contract), and when two paths fit prefer the one extending the established model over a one-off
   room. A novel concept, special case, boundary move, or fragmenting convenience feature is a model
   extension whose design decision is stated in the PR or commit, never a quiet deviation. Update
   repository documentation only where it is a maintained source of truth or the issue requires a
   recorded decision.
3. Add tests at the acceptance boundary: a regression test for a bug, focused behavior tests for a
   feature. Never rewrite tests to bless incorrect behavior or broaden into unrelated cleanup.
4. Treat security, auth, secrets, migrations, runtime flags, and destructive operations as
   high-risk. Fail closed where the issue requires it; never commit credentials or weaken safeguards
   to make a test pass.
5. Keep scope honest. If implementation reveals a distinct follow-up, leave it out and report it; do
   not silently turn one issue into a refactor campaign.

## Step 3 — verify in risk order

Run the cheapest relevant checks first, then the repository's prescribed gate:

1. changed-area unit/regression tests;
2. compile/typecheck/lint for affected units;
3. integration or repository-wide tests required by repo instructions;
4. the **actual changed boundary**: build/run the container, CLI, migration, runtime config, HTTP
   route, or browser flow when unit tests cannot prove deployment behavior.

A green unit suite does not prove container startup, generated runtime files, routing, profile/bean
selection, migration validity, or browser deep links. Exercise those directly when changed. For a
runtime flag, verify its default, valid override, invalid value, profile/config precedence, and the
baked artifact when startup hooks can be bypassed; an unsupported deployment profile must not be
overrideable into an incomplete feature.

If a broad gate is red, classify it before proceeding:

- **Introduced by this branch** → fix it.
- **Pre-existing baseline** → prove it using documented repo evidence or the same command at the
  base commit in a clean worktree; run the issue-specific slice green and disclose the exact
  baseline failure.
- **Environment/tooling** → repair safely when local-only, otherwise disclose the concrete blocker.

Never call the repository fully green when a gate is red. A proven unrelated baseline failure may be
disclosed in the PR; a required branch check that will block merge remains a blocker.

## GATE — issue acceptance and diff audit

Before delivery:

- map every issue acceptance item to a code change, test, or explicit evidence;
- inspect `git diff --check`, `git diff`, and `git status`;
- verify no unrelated files, generated junk, secrets, debug code, or accidental lockfile changes;
- rerun the load-bearing issue checks after the final edit;
- when retiring a stub, flag, or profile restriction, exhaustively search source and maintained docs
  for superseded status markers; qualify same-named components across stacks.
- verify the change fits the existing model: no new concept, special case, boundary move, or
  fragmenting convenience feature that the issue did not record as a design decision; no surprise
  path added as a side effect; and nothing that covers more domain than the model intends. In a
  partitioned contract run `idd-plan/scripts/contract.sh owner <contract-path> <changed files>`:
  every changed file resolves to the issue's context, or the issue records the cross-context design
  decision; a `none` or `ambiguous` file is a scope question to raise, never a cheap fix.

An ambiguous or unproved acceptance item is said so, never claimed complete; a reviewable
implementation may still open a non-closing PR.

## Step 4 — commit and open the PR

1. Stage only issue-owned paths explicitly and commit with N-4 subjects, per the shared conventions
   in the sibling `idd-plan/references/conventions.md`. Commit messages, branch names, and PR/issue
   text are permanent provider surfaces no later publication can purge — retained pull-request refs
   outlive any history rewrite — so never name a private companion repository, document, or section
   in them; give the rationale generically instead. Then run the sibling
   `idd-plan/scripts/line-width.sh check origin/<default>`: rewrap every reported line to 100
   characters, or list its path on the repository's `Formatter-owned:` line only when a formatter,
   generator, package manager, or recorder lays it out.
2. Push the dedicated branch. Open a focused PR into the integration branch, never the release
   branch, titled character-identically to the issue (N-2), using the repository template. Include
   summary, verification commands/results, proven baseline failures, and risks/follow-ups. Declare
   exactly one `Delivery-Type: <type>` field in the body with an N-4 type; `/idd-land` composes the
   squash subject from it and stops without it. Use `Closes #N` only when every acceptance item is
   proved and the issue belongs to this repository; otherwise use a non-closing `Refs #N` (same
   repo) or `Refs owner/repo#N`.
3. Read back the PR URL and state. Do not merge it, delete the branch, deploy, or close the issue
   directly. Merge policy and CI remain the repository's gate.

## Completion output

Return only:

- issue and chosen outcome;
- key implementation points;
- verification (green checks plus precisely named baseline/tooling limitations);
- commit, PR URL, and current lifecycle state;
- exactly one next action (when the PR is ready, use the active runner's syntax: `$idd-land #N` in
  Codex, `/idd-land #N` in Claude Code, `/skill:idd-land #N` in Pi, or `Use idd-land for issue N` in
  OpenCode; otherwise return the named blocker);
- excluded follow-ups, if any.

A paused run stays on its issue branch; resume from the live issue, branch diff, and PR state, never
a separate trace file.
