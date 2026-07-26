# IDD Constitution

The law governing `/idd`, `/idd-evolve`, and changes to this repository. Evolution is a filter, not an accumulator: kept lessons change the skills and reach git; rejected lessons leave no log.

## Article 1 — Preserve the lightweight boundary

IDD delivers one well-scoped issue in an existing software repository from live issue intent through native verification and a linked PR. It does not create PRDs, golden-file suites, sibling repositories, trace artifacts, mandatory review waves, deployment, auto-merge, or manual issue closure. `/idd-evolve` is a separate methodology-maintenance command; none of its machinery enters project repositories.

## Article 2 — Pass or nothing

A candidate has two outcomes:

- **Pass** → minimally edit the methodology, validate, commit, and push. Git history records what and why.
- **Fail** → do nothing. No research log, proposal queue, patterns ledger, or deferred list.

## Article 3 — Evidence and value

A change passes only when it is high-value, proven, not already covered, and smaller than the friction it removes. A mechanically reproducible defect or established practice may be proven once; a behavioral generalization normally needs multiple independent runs. Prefer deletion or replacement over addition.

## Article 4 — Put instructions at the right layer

Structural, behavioral, and validation lessons belong in skills. Runtime/tool-specific accidents do not, unless they reveal a general issue-delivery boundary. If a step has one mechanically correct output—installation, structural validation, counts, transforms, or git plumbing—script it; prose remains for judgment.

## Article 5 — Size and structure gates

- `skills/idd/SKILL.md` ≤ 160 lines.
- `skills/idd-evolve/SKILL.md` ≤ 80 lines.
- Every skill has valid Agent Skills frontmatter, an interface hint, orientation before action, and a quality gate.
- `/idd-evolve` reads this constitution first and uses pass-or-nothing evolution.
- Cross-references resolve and `bash scripts/validate.sh` passes.

Over cap means compress in the same change or revert.

## Article 6 — Commit and publish

Every kept evolution reaches `maximalfocus/idd-skills` on `main`. Stage only explicit task-owned paths; never `git add -A`. Pull/rebase before committing, use a meaningful `evolve:` or `fix:` message, never force-push, and push normally. Project repositories remain governed by their own review policy.
