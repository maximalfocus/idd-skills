---
name: idd-plan
description: "Bootstrap a greenfield IDD product PRD, plan the next issue from an existing sibling {project}-prd repository, or reconcile its progress tracker with verified live GitHub state."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
argument-hint: "[project-name|--reconcile]"
---

# /idd-plan — start or continue an issue-driven product

Bootstrap a concise product contract, or bridge an existing private `{project}-prd` repository to its implementation repository, without importing CDD's artifact pipeline. Greenfield mode publishes only `PRD.md` and `PROGRESS.md` to a private repository by default. Existing-project default mode is read-only and recommends one issue; reconcile mode updates only the tracker.

A greenfield invocation authorizes discovery, drafting, private PRD repository creation, initial commit, and push unless the user explicitly asks for draft-only output. Creating the implementation repository or an issue remains separate. `/idd-plan --reconcile` authorizes a tracker commit/push; successful `/idd-land` supplies the same authority automatically.

## Orient and select the mode

1. Resolve this skill's physical source repository. From a checkout, run `scripts/resolve-prd-pair.sh`; the only automatic association is the exact sibling `{implementation-name}-prd` with matching GitHub origins plus `PRD.md` and `PROGRESS.md`. Read both repositories' instructions. GitHub is lifecycle authority and the PRD is requirement authority.
2. Use greenfield mode only when the user asks to plan a new product and no PRD source exists. Resolve a unique project slug, GitHub owner, private visibility, and workspace parent; never overwrite a path or repository. `--reconcile` always requires an existing exact pair and clean trees.
3. Existing modes fetch the live issue/PR state, comments, checks, closing links, and squash commits needed for each conclusion. Parse requirements, slices, dependencies, release boundaries, tracker links, and explicit deferrals; preserve contradictions.

## Greenfield mode — clarify and author the product contract

1. Clarify intended users, problem, outcomes, workflows, security/data/API behavior, scope, non-goals, release boundary, and observable acceptance. Scale discovery to unresolved domain complexity: a small product gets few questions; a large, ambiguous, or high-risk domain gets more. Ask one decision at a time only when its answer materially changes the product, offer real alternatives with a recommendation, and stop when acceptance is unambiguous. Select technology and implementation details autonomously from best practices unless they change product behavior/risk or the user states a preference.
2. Draft one concise `PRD.md` with stable requirement IDs and small, dependency-ordered, independently reviewable delivery slices — one issue per slice, delivered issue-by-issue, never a monolithic slice for the whole project; every slice states its explicit dependencies and its own acceptance, which must never require a later slice's deliverable, and no slice claims a gate that only applies after all slices land. Draft `PROGRESS.md` with the same IDs, explicit status semantics, and no invented GitHub evidence. Do not create a PLAN file or speculative issue backlog; recommend only the first ready slice as an issue contract.
3. Once the complete contract is settled, write only those two files, run `scripts/init-prd.sh <path> <owner>/<project>-prd`, and read back the private remote and commit. If the user requested draft-only output, present both complete drafts and the recommended first issue without writing or publishing. Stop before implementation-repository or issue creation unless separately authorized.

## Default mode — recommend one next issue

1. Reconcile mentally, without editing, what is landed, partially landed, active, blocked, and unstarted. Do not equate merged code with release validation, and do not advance post-release work ahead of unmet initial-release dependencies.
2. Build a dependency-ordered view of the remaining slices, then select only the first independently reviewable outcome. Prefer completing a partially landed slice over starting a later one unless a recorded dependency blocks it.
3. Draft a compact, public-safe issue contract: source requirement and slice IDs, outcome, publishable evidence, acceptance criteria, non-goals, likely boundary, and verification. Reference rather than quote private rationale or source material; do not invent implementation details or create a speculative backlog.

## Reconcile mode — persist verified progress

1. Pull each clean default branch with `--ff-only`. Re-read every tracker-linked issue, PR, and commit needed for the changed rows. When called by `/idd-land`, also bind the supplied issue, PR, and squash commit to the matching requirement slice; stop rather than guess when that mapping is ambiguous.
2. Edit only `PROGRESS.md`. Add verified issue/PR/squash links, apply the tracker's existing status semantics, and preserve distinctions such as partially landed, landed, and validated. Never copy private PRD content into the public repository or claim acceptance not proven by live evidence.
3. Run repository instructions, validate referenced requirement IDs and Markdown links, then run `git diff --check`. Audit the complete diff for lifecycle-only changes. If byte-identical, report already reconciled; otherwise commit `progress: reconcile <owner/repo>#<issue>` (or an equally specific repair subject), push the PRD default branch normally, and read back the remote commit.

## GATE — planning and reconciliation integrity

Greenfield requires material product decisions settled, PRD/tracker ID agreement, private visibility readback unless draft-only, and no technical-question drift. Existing modes require an exact pair and complete live-state reads. Every mode permits one next issue at most, dependency-respecting order, and no invented lifecycle evidence. Reconcile leaves both repositories clean and synchronized with only `PROGRESS.md` changed; failure after merge is reported as `landed, PRD reconciliation incomplete` and never rolls back the merge.

## Completion

Greenfield returns the approved PRD/tracker repository and one next issue contract. Existing default returns discrepancies, ordered remaining slices, and one issue contract. Reconcile returns changed rows, evidence URLs and squash, commit/push state, and incomplete postconditions. Every mode gives exactly one next action (`/idd-issue …`, implementation-repository authorization, or the named blocker).
