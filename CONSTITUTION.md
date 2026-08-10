# IDD Constitution

The law governing `/idd-plan`, `/idd-issue`, `/idd`, `/idd-land`, `/idd-auto`, `/idd-evolve`, and changes to this repository. Evolution is a filter, not an accumulator: kept lessons change the skills and reach git; rejected lessons leave no log.

## Article 1 — Preserve the lightweight boundary

`/idd-plan` has one bounded greenfield exception: after product-requirement discovery and explicit approval, bootstrap mode may create a private `{project}-prd` repository containing only `PRD.md` and `PROGRESS.md`. It never creates a plan file, implementation repository, issue, branch, or PR. For an existing convention-linked pair, default mode recommends at most one next issue without mutation; reconcile mode may update only its existing `PROGRESS.md` from verified live lifecycle evidence. `/idd-issue` creates one implementation-ready GitHub issue from evidence after explicit authorization; it does not implement, branch, or open a PR. `/idd` delivers one well-scoped live issue through native verification and a linked PR. `/idd-land` is the separate landing phase: direct invocation or one active explicit `/idd-auto` run may authorize it to squash-merge one validated PR, close its issue, clean its branches, and automatically reconcile an exact associated PRD tracker, but never bypass red gates. `/idd-auto` is the only full-loop exception: one explicit invocation may repeat the current plan, create, implement, and land phases for an exact pair, one issue at a time, until PRD implementation completion or a fail-closed blocker. No command creates golden-file suites, trace artifacts, mandatory review waves, deployment, speculative backlogs, or parallel delivery. `/idd-evolve` is separate methodology maintenance; no command adds methodology traces to project repositories.

## Article 2 — Pass or nothing

A candidate has two outcomes:

- **Pass** → minimally edit the methodology, validate, commit, and push. Git history records what and why.
- **Fail** → do nothing. No research log, proposal queue, patterns ledger, or deferred list.

## Article 3 — Evidence and value

A change passes only when it is high-value, proven, not already covered, and smaller than the friction it removes. A mechanically reproducible defect or established practice may be proven once; a behavioral generalization normally needs multiple independent runs. For `/idd-plan`, primary evidence is PRD-to-issue selection quality, live/tracker discrepancies, and post-landing reconciliation outcomes. For `/idd-issue`, primary evidence is the source request, duplicate-search result, created issue and edits/comments, and downstream implementation friction when available. For `/idd-auto`, primary evidence is repeated sequential lifecycle friction plus its live-state resume and gate-preservation outcomes. Planning and issue creation never auto-invoke evolution or create lessons logs; `/idd-evolve post-plan` and `post-create` apply the same pass-or-nothing gate. Prefer deletion or replacement over addition.

## Article 4 — Put instructions at the right layer

Structural, behavioral, and validation lessons belong in skills. Runtime/tool-specific accidents do not, unless they reveal a general issue-delivery boundary. If a step has one mechanically correct output—installation, structural validation, counts, transforms, or git plumbing—script it; prose remains for judgment.

## Article 5 — Size and structure gates

- `skills/idd-plan/SKILL.md` ≤ 90 lines.
- `skills/idd-issue/SKILL.md` ≤ 70 lines.
- `skills/idd/SKILL.md` ≤ 160 lines.
- `skills/idd-land/SKILL.md` ≤ 120 lines.
- `skills/idd-auto/SKILL.md` ≤ 120 lines.
- `skills/idd-evolve/SKILL.md` ≤ 80 lines.
- Every skill has valid Agent Skills frontmatter, an interface hint, orientation before action, and a quality gate.
- `/idd-plan` requires approval before greenfield PRD publication, product-only clarification proportional to unresolved domain complexity, exact association for existing pairs, read-only default planning, at most one next issue, live-state authority, and tracker-only reconciliation.
- `/idd-issue` requires explicit creation authority, open-and-closed duplicate search, and read-back verification.
- `/idd-land` requires explicit invocation, an acceptance/residual gate, and verified postconditions.
- `/idd-auto` requires explicit invocation, an exact PRD pair, one active issue, current constituent gates, live-state resume, and a final completion audit.
- `/idd-evolve` reads this constitution first and uses pass-or-nothing evolution for planning, implementation, and issue-creation evidence.
- Cross-references resolve and `bash scripts/validate.sh` passes.

Over cap means compress in the same change or revert.

## Article 6 — Commit and publish

Every kept evolution reaches `maximalfocus/idd-skills` on `main`. Stage only explicit task-owned paths; never `git add -A`. Pull/rebase before committing, use a meaningful `evolve:` or `fix:` message, never force-push, and push normally. Explicit bootstrap approval authorizes the initial private PRD commit/push; explicit `/idd-land` or `/idd-auto` authority permits automatic verified `PROGRESS.md` commit/push in the exact associated PRD repository. Failure after merge is disclosed and resumable. Project repositories otherwise remain governed by their own review policy.
