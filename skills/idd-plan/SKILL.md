---
name: idd-plan
description: >-
  Bootstrap a greenfield IDD product PRD, reconstruct one from an already-implemented repository,
  plan the next issue from an existing sibling {project}-prd repository, or reconcile its progress
  tracker with verified live GitHub state.
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd-plan — start or continue an issue-driven product

Bootstrap a product contract from new requirements or implemented source, or bridge an existing
private `{project}-prd` to its implementation repository. Both bootstrap modes publish only
`PRD.md` and `PROGRESS.md` to a private repository, and authorize discovery, drafting, repository
creation, initial commit, and push unless the user explicitly asks for draft-only output; creating
the implementation repository or an issue stays separate. Default mode is read-only and recommends
one issue. `--reconcile` updates only the tracker through the PRD's one open progress-batch pull
request, as does a successful `/idd-land`. No mode creates a PLAN file or a speculative backlog.

## Orient and select the mode

1. Resolve this installed skill directory and run its bundled `scripts/resolve-prd-pair.sh`: the
   only automatic association is `{implementation-name}-prd` with matching origins and PRD/tracker.
   Before any existing-contract reads or gates, run
   `scripts/progress-pr.sh sync <contract-path>`; stop on refusal. Read repository instructions.
   Run `scripts/contract.sh list <contract-path>`: names mean a partitioned contract whose root
   `PRD.md` is the index and root `PROGRESS.md` the portfolio panel; `--context <name>` selects one,
   a reading mode reads the index plus that context, and a writing mode passes
   `scripts/contract.sh gate <contract-path>` first. GitHub is lifecycle authority; the PRD is
   requirement authority. Default mode permits only bundled sync's local branch selection,
   default-import merge, and guard hook; never edits content, remote refs, issues, or the tracker.
2. Select the mode by what exists. No product and no PRD source: greenfield. An implemented
   repository with real delivery history and no sibling PRD: reconstruct, also named by
   `--reconstruct`; `--reconstruct --scope <path>...` bounds it to one context's paths or globs in a
   repository too large to read entire, and with `--context <name>` against an existing pair admits
   a context its index does not list yet, never by widening an existing one. An exact pair: default,
   or `--reconcile`, which also requires clean trees. Both bootstrap modes resolve a unique project
   slug, GitHub owner, private visibility, and workspace parent, and never overwrite a path or
   repository.
3. Existing modes fetch the live issue/PR state, comments, checks, closing links, and squash commits
   each conclusion needs; parse requirements, slices, dependencies, release boundaries, tracker
   links, and explicit deferrals, preserving contradictions.

## Greenfield mode — clarify and author the product contract

1. Clarify users, problem, outcomes, workflows, security/data/API behavior, scope, non-goals,
   release boundary, and observable acceptance, scaling discovery to unresolved domain complexity.
   Ask one decision at a time only when its answer materially changes the product, offer real
   alternatives with a recommendation, and stop when acceptance is unambiguous. Choose technology
   and implementation details autonomously unless they change product behavior/risk or the user
   states a preference.
2. Draft one concise `PRD.md` as a coherent design contract: consistent concepts and naming, an
   explicit domain boundary and non-goals, stable requirement IDs, and small, dependency-ordered,
   independently reviewable slices that partition the domain rather than add convenience rooms —
   one issue per slice, never one monolithic slice. Each slice states how it preserves or extends
   the model, its dependencies, and its own acceptance, which never requires a later slice's
   deliverable or a gate that applies only after all slices land. A slice owns a section only while
   ready or active: once validated, its acceptance moves into the requirement it extends or becomes
   a new requirement, and the slice collapses to one row of the Delivery slices table, a `prd`
   commit by the user. Write `### Preserved artifacts`: one row per artifact a regeneration must
   carry over unchanged — repository, path, why it is not regenerable, how final acceptance verifies
   it — from candidates the user names, never an invented path; an empty manifest is written
   explicitly as `None declared`. Draft `PROGRESS.md` as an implementation control panel with the
   same IDs, explicit status semantics, and only the baseline plus rows that answer what is ready,
   active, blocked, or missing acceptance; never an append-only or commit log, and no invented
   GitHub evidence. Recommend only the first ready slice as an issue contract.
3. Once the contract is settled, write only those two files, pass the bundled
   `scripts/prd-size-gate.sh PRD.md`, run `scripts/init-prd.sh <path> <owner>/<project>-prd`, and
   read back the private remote and commit. For draft-only output, present both complete drafts and
   the recommended first issue without writing or publishing.

## Reconstruct mode — derive the contract from implemented source

1. Read the whole implemented surface — with `--scope`, the surface those paths cover — every
   tracked entry point, its tests, build/verification gate, documentation, retained charter, and the
   live issue, PR, and commit history that touches it. Name the exact source commit described and,
   when bounded, the scope: write those globs under `## Scope`, the contexts referenced under
   `## Depends on` by name and requirement ID without restating their behavior, and the rest of the
   repository as an explicit non-goal; the first context of a large product is normally the shared
   foundation. Run the bundled `scripts/manifest.sh candidates <implementation-or-scope-paths>`: it
   proposes only classes with observed evidence (a constitution, versioned schemas or rule packs,
   golden or fixture directories, frozen protocol documents, lockfiles, decision logs, dated
   acceptance or cohort records), and a candidate enters `### Preserved artifacts` only when the
   user confirms it with a stated reason. Ask the user only what the source cannot answer — release
   boundary, publication posture, a disputed non-goal — never what the code already states.
2. Write requirements descriptively: each states behavior the source implements at that commit, with
   rationale quoted only from repository evidence (comments, documentation, charters, issues, PRs).
   Attribute no intent the repository does not state; stay silent where the implementation is.
3. Collapse all implemented scope into one verified implementation baseline in the PRD and
   `PROGRESS.md`, bound to the named source commit and real repository-gate result. Git and GitHub
   retain chronology: never turn each past commit, issue, or PR into a slice or tracker row. Add
   slices only for explicitly accepted remaining feature, changed-behavior, or repair outcomes with
   real current lifecycle evidence, and never invent issue numbers. Mark nothing `validated` without
   live acceptance evidence; state verification gaps explicitly. Pass `scripts/prd-size-gate.sh
   PRD.md`, publish through `scripts/init-prd.sh`, then continue in default mode. With
   `--context <name>`, write `contexts/<name>/PRD.md` and `PROGRESS.md`, add the context's row to
   the index `## Contexts` table and the portfolio panel — creating both root files when the pair
   is new — and pass `scripts/contract.sh gate <contract-path>`. Bootstrap pushes only once;
   existing-context contract changes require a user's `prd` pull request, never a default push.

## Default mode — recommend one next issue

1. Without editing, assess landed, partial, active, blocked, and unstarted work. In a partitioned
   contract honor `--context`; otherwise choose active work or the earliest unmet dependency from
   the portfolio. Read the index and that context. Merged code is not release validation;
   post-release work never advances ahead of unmet initial-release dependencies.
2. Select one independently reviewable outcome in dependency order; prefer unblocked partial work.
3. Draft a compact, public-safe issue contract: requirement and slice IDs, the owning context name
   as label when partitioned, outcome, publishable evidence, acceptance criteria, non-goals, likely
   boundary, and verification. Reference, never quote, private rationale; invent no details.

## Reconcile mode — persist verified progress

1. Pull the clean implementation default branch with `--ff-only`, run the bundled
   `scripts/progress-pr.sh sync <contract-path>`, and re-read every tracker-linked issue, PR, and
   commit the changed rows need. When called by `/idd-land`, bind the supplied issue, PR, and squash
   commit to the matching slice; stop rather than guess when that mapping is ambiguous.
2. Edit only `PROGRESS.md` — in a partitioned contract the owning context's, found by the landed
   issue's context label, plus its portfolio row — as the implementation control panel: record
   current issue/PR/squash evidence in the owning row under the existing status semantics, replacing
   superseded state. At a completed release boundary, collapse terminal rows into one baseline with
   requirement coverage, source commit, and verification result; keep only that baseline and rows
   that still guide implementation. Never copy private PRD content into the public repository or
   claim acceptance live evidence does not prove. Never edit `PRD.md` or its manifest: when landed
   behavior contradicts requirement prose, report `PRD text stale` naming the requirement, repaired
   by a user's `prd` commit. Run the bundled `scripts/manifest.sh drift <contract-path>`,
   `scripts/prd-fold-gate.sh PRD.md PROGRESS.md`, and `scripts/prd-size-gate.sh PRD.md`; report an
   unlisted tracked file as drift, a validated slice still owning a PRD section as `PRD slices
   unfolded`, and an over-budget section or contract as `PRD over budget` naming it, changing
   nothing in `PRD.md` — the repair is folding, compressing, or narrowing the domain boundary in a
   `prd` commit, never a raised budget. When partitioned also run
   `scripts/contract.sh gate <contract-path>` over the index and every context.
3. Run the bundled `scripts/tracker-gate.sh PROGRESS.md`, repository instructions, requirement ID
   and Markdown link validation, and `git diff --check`. The gate's budgets live in the script and
   change only through `/idd-evolve`; a stopped gate is reported with its line and cell and repaired
   only by this mode folding and replacing state under the tracker's own update rule. Audit the
   diff for lifecycle-only changes. If byte-identical, report already reconciled; otherwise run
   `scripts/progress-pr.sh push <contract-path> '<subject>' <tracker-paths>` with `progress:
   reconcile <owner/repo>#<issue>` or an equally specific repair subject and read back its commit.
   The batch merges only at a milestone — a row set `validated`, a release boundary collapsed, the
   step before `/idd-acceptance`, `/idd-publish`, or the `/idd-auto` completion audit, or a direct
   user `--reconcile` — through `scripts/progress-pr.sh merge <contract-path> '<subject>'`, even
   with no new diff. Exit 2 is `PRD batch awaiting review`; other failures are resumable plumbing
   blockers, never review refusals. New batches use `progress/batch`; failed pushes retain evidence.
   Retry outages with push; after a race, preserve the checkout, sync a clean clone, and reconcile.

## GATE — planning and reconciliation integrity

Bootstrap requires PRD/tracker ID agreement, an explicit manifest, one coherent model, a passing
size gate — and contract gate when partitioned — and private visibility readback unless draft-only;
greenfield also requires settled material product decisions and no technical-question drift, and
reconstruct a named source commit with the remainder of a scoped repository a stated non-goal.
Existing modes require an exact pair and complete live-state reads. Every mode permits at most one
next issue, in dependency order, with no invented lifecycle evidence. Reconcile passes the tracker
gate, never edits `PRD.md`, and leaves both repositories clean and synchronized with only
`PROGRESS.md` changed; failure after merge is reported as `landed, PRD reconciliation incomplete`
and never rolls back the merge. Return the mode's result — repository and first issue contract;
source commit, inventory, next issue or verification gaps; discrepancies, ordered slices, issue
contract; or changed rows, evidence, commit/push state — and one next action (`/idd-issue …`,
implementation-repository authorization, a named verification gap, or the named blocker).
