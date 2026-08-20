# IDD Constitution

The law governing `/idd-plan`, `/idd-issue`, `/idd`, `/idd-land`, `/idd-auto`, `/idd-evolve`, and changes to this repository. Evolution is a filter, not an accumulator: kept lessons change the skills and reach git; rejected lessons leave no log.

## Article 1 — Preserve the lightweight boundary

`/idd-plan` has one bounded bootstrap exception, reached either after product-requirement discovery (greenfield) or from an already-implemented repository's source and delivery history (reconstruct): bootstrap mode creates and pushes a private `{project}-prd` repository containing only `PRD.md` and `PROGRESS.md` by default; an explicit draft-only request suppresses publication. Reconstruct describes only behavior the implementation already has, collapses implemented scope to one verified baseline, and never recreates Git history as delivery slices or invents lifecycle evidence. It never creates a plan file, implementation repository, issue, branch, or PR. For an existing convention-linked pair, default mode recommends at most one next issue without mutation; reconcile mode may update only its existing `PROGRESS.md` from verified live lifecycle evidence. `/idd-issue` creates one implementation-ready GitHub issue from evidence after explicit authorization; it does not implement, branch, or open a PR. `/idd` delivers one well-scoped live issue through native verification and a linked PR. `/idd-land` is the separate landing phase: direct invocation or one active explicit `/idd-auto` run may authorize it to squash-merge one validated PR, close its issue, clean its branches, and automatically reconcile an exact associated PRD tracker, but never bypass red gates. `/idd-auto` is the only full-loop implementation exception: one explicit invocation may privately bootstrap the exact missing implementation sibling of an existing clean PRD repository, then repeat the current plan, create, implement, and land phases for that exact pair, one issue at a time, until PRD implementation completion or a fail-closed blocker. `/idd-publish` is the separate publication phase: one explicit invocation may complete one publication-preparation issue and then make only the implementation repository public after exposure and anonymous-readback gates; its companion PRD remains private. No command creates golden-file suites, trace artifacts, mandatory review waves, deployment, speculative backlogs, or parallel delivery. `/idd-evolve` is separate methodology maintenance; no command adds methodology traces to project repositories.

`/idd-acceptance` is the separate final integrated acceptance phase: it verifies the completed product at its real user-facing boundary and never deploys or changes the contract.

## Article 2 — Pass or nothing

A candidate has two outcomes:

- **Pass** → minimally edit the methodology, validate, commit, and push. Git history records what and why.
- **Fail** → do nothing. No research log, proposal queue, patterns ledger, or deferred list.

## Article 3 — Evidence and value

A change passes only when it is high-value, proven, not already covered, and smaller than the friction it removes. A mechanically reproducible defect or established practice may be proven once; a behavioral generalization normally needs multiple independent runs. For `/idd-plan`, primary evidence is PRD-to-issue selection quality, live/tracker discrepancies, post-landing reconciliation outcomes, and reconstruction fidelity to implemented source. For `/idd-issue`, primary evidence is the source request, duplicate-search result, created issue and edits/comments, and downstream implementation friction when available. For `/idd-auto`, primary evidence is repeated sequential lifecycle friction plus its live-state resume and gate-preservation outcomes. Planning and issue creation never auto-invoke evolution or create lessons logs; `/idd-evolve post-plan` and `post-create` apply the same pass-or-nothing gate. Prefer deletion or replacement over addition. A change must also leave already-delivered issues the same or better: name the delivery it would most likely have degraded, clear it, or narrow the rule to where it holds.

## Article 4 — Put instructions at the right layer

Structural, behavioral, and validation lessons belong in skills. Runtime/tool-specific accidents do not, unless they reveal a general issue-delivery boundary. If a step has one mechanically correct output—installation, structural validation, counts, transforms, or git plumbing—script it; prose remains for judgment.

## Article 5 — Size and structure gates

- `skills/idd-plan/SKILL.md` ≤ 90 lines.
- `skills/idd-issue/SKILL.md` ≤ 70 lines.
- `skills/idd/SKILL.md` ≤ 160 lines.
- `skills/idd-land/SKILL.md` ≤ 120 lines.
- `skills/idd-auto/SKILL.md` ≤ 120 lines.
- `skills/idd-evolve/SKILL.md` ≤ 80 lines.
- `skills/idd-publish/SKILL.md` ≤ 120 lines.
- `skills/idd-acceptance/SKILL.md` ≤ 120 lines.
- Every skill has valid Agent Skills frontmatter, an interface hint, orientation before action, and a quality gate.
- `/idd-plan` requires private-by-default bootstrap publication with a draft-only opt-out, product-only clarification proportional to unresolved domain complexity, source-traceable descriptive requirements and one verified implementation baseline when reconstructing, exact association for existing pairs, read-only default planning, at most one next issue, live-state authority, and tracker-only reconciliation that keeps `PROGRESS.md` an implementation control panel rather than a commit or delivery log.
- `/idd-issue` requires explicit creation authority, open-and-closed duplicate search, and read-back verification.
- `/idd-land` requires explicit invocation, an acceptance/residual gate, and verified postconditions.
- `/idd-auto` requires explicit invocation, an exact PRD source and pair (privately bootstrapping only its uniquely missing implementation sibling), one active issue, current constituent gates, live-state resume, a final completion audit, and no publication invocation.
- `/idd-auto` acceptance failures must distinguish an accepted-requirement repair issue from a genuinely new or changed requirement; only the latter pauses for explicit scope authorization and PRD/slice revision, and project defects never invoke `/idd-evolve`.
- `/idd-publish` requires explicit invocation, an exact private pair, one preparation issue, a scripted exposure audit covering every commit message and retained pull-request ref with denylist terms matched by bare stem, implementation-only visibility mutation, anonymous readback, and private PRD verification.
- `/idd-acceptance` requires an exact completed pair, a real product boundary, complete applicable journeys, readiness and teardown evidence, failure classification, and no deployment or residual acceptance.
- `/idd-evolve` reads this constitution first and uses pass-or-nothing evolution for planning, implementation, and issue-creation evidence.
- Cross-references resolve and `bash scripts/validate.sh` passes.

Over cap means compress in the same change or revert.

## Article 6 — Commit and publish

Every kept evolution reaches `maximalfocus/idd-skills` on `main`. Stage only explicit task-owned paths; never `git add -A`. Pull/rebase before committing, use a meaningful `evolve:` or `fix:` message, never force-push, and push normally. Greenfield `/idd-plan` authorizes the initial private PRD commit/push unless the user requests draft-only output; explicit `/idd-land` or `/idd-auto` authority permits automatic verified `PROGRESS.md` commit/push in the exact associated PRD repository. Failure after merge is disclosed and resumable. Project repositories otherwise remain governed by their own review policy.
