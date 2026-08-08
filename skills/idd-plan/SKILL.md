---
name: idd-plan
description: "Plan the next Issue-Driven Development step from an existing sibling {project}-prd repository, or reconcile its progress tracker with verified live GitHub state. Use when asked what to implement next, to plan from a PRD, or to repair PRD progress after landing."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
argument-hint: "[--reconcile]"
---

# /idd-plan — choose the next issue from an existing PRD

Bridge an existing private `{project}-prd` repository to its public implementation repository without importing CDD's artifact pipeline. Default mode is read-only and recommends one next issue. Reconcile mode updates only the existing progress tracker; neither mode creates a PRD, plan file, implementation issue, branch, or PR.

An explicit `/idd-plan --reconcile` authorizes a tracker commit and push. A successful `/idd-land` invocation supplies the same authority automatically for its convention-linked sibling PRD repository; users do not invoke reconciliation separately in the normal lifecycle.

## Resolve the project pair

1. Resolve this skill's physical source repository and run `scripts/resolve-prd-pair.sh` from either checkout. The only automatic association is an exact sibling `{implementation-name}-prd` repository whose GitHub origin is `{owner}/{implementation-name}-prd` and which already contains `PRD.md` and `PROGRESS.md`. Never guess another path or create the repository/files.
2. Read instructions in both repositories. Require clean working trees before reconcile; default planning may inspect an unrelated dirty tree but shall not modify it. Fetch live issue and PR states, comments, checks, closing links, and squash commits with `gh`; GitHub is lifecycle authority, while the PRD is requirement authority.
3. Parse requirements, delivery slices, dependencies, release boundaries, existing tracker links, and explicit deferrals. Preserve uncertainty when requirement-to-slice mapping is absent or contradictory.

## Default mode — recommend one next issue

1. Reconcile mentally, without editing, what is landed, partially landed, active, blocked, and unstarted. Do not equate merged code with release validation, and do not advance post-release work ahead of unmet initial-release dependencies.
2. Build a dependency-ordered view of the remaining slices, then select only the first independently reviewable outcome. Prefer completing a partially landed slice over starting a later one unless a recorded dependency blocks it.
3. Draft a compact, public-safe issue contract: source requirement and slice IDs, outcome, publishable evidence, acceptance criteria, non-goals, likely boundary, and verification. Reference rather than quote private rationale or source material; do not invent implementation details or create a speculative backlog.

## Reconcile mode — persist verified progress

1. Pull each clean default branch with `--ff-only`. Re-read every tracker-linked issue, PR, and commit needed for the changed rows. When called by `/idd-land`, also bind the supplied issue, PR, and squash commit to the matching requirement slice; stop rather than guess when that mapping is ambiguous.
2. Edit only `PROGRESS.md`. Add verified issue/PR/squash links, apply the tracker's existing status semantics, and preserve distinctions such as partially landed, landed, and validated. Never copy private PRD content into the public repository or claim acceptance not proven by live evidence.
3. Run repository instructions, validate referenced requirement IDs and Markdown links, then run `git diff --check`. Audit the complete diff for lifecycle-only changes. If byte-identical, report already reconciled; otherwise commit `progress: reconcile <owner/repo>#<issue>` (or an equally specific repair subject), push the PRD default branch normally, and read back the remote commit.

## GATE — planning and reconciliation integrity

Require an exact repository pair, complete live-state reads for every conclusion, one next issue at most, dependency-respecting order, and no invented lifecycle evidence. Reconcile must leave both repositories clean and synchronized, with only `PROGRESS.md` changed in its commit. A post-merge reconciliation failure is reported as `landed, PRD reconciliation incomplete`; it never rolls back the merge and is resumable through `/idd-land` or explicit `/idd-plan --reconcile` repair.

## Completion

Default mode returns the live/tracker discrepancy summary, ordered remaining slices, one recommended issue contract, and exactly one next action (`/idd-issue …` or the named blocker). Reconcile mode returns the changed rows, evidence URLs and squash, PRD commit/push state, and any incomplete postcondition.
