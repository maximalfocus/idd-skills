# idd-skills repository conventions

## Sources of truth

Author `/idd`, `/idd-plan`, `/idd-issue`, `/idd-implement`, `/idd-land`, `/idd-auto`,
`/idd-acceptance`, `/idd-publish`, and `/idd-evolve` in their matching `skills/*/SKILL.md` sources.
`CONSTITUTION.md` governs methodology changes. Do not create a `commands/` mirror; Claude Code,
Codex, Pi, and OpenCode consume the same Agent Skills sources through symlinks created by
`scripts/install.sh` (OpenCode discovers the shared `~/.agents/skills/` links). Keep skill inputs
portable: runners that do not inject `$ARGUMENTS` must be able to use the user's request.

## Scope

IDD is the lightweight issue workflow. `/idd-plan` may bootstrap only a private PRD plus progress
tracker, after product-requirement approval or reconstructed from an implemented repository's source
and delivery history; otherwise it consumes an exact convention-linked pair, recommends one next
issue, or reconciles verified tracker state. It never creates plan files or issues. `/idd-issue`
creates one evidence-backed issue; `/idd-implement` must not absorb CDD's golden-file, trace,
mandatory peer-review, acceptance-wave, or deploy machinery. `/idd` is the entry point: it routes
one request to one phase and adds no authority, so a phase that requires explicit invocation is
reached through it only when the request names that action (Constitution Article 5). Planning
inference reaches only read-only default mode; bootstrap, reconstruct, and reconcile require the
request to name that mode. `/idd-land` is the gated merge/closure phase and reconciles an exact
associated PRD after landing. `/idd-auto` may sequence those current phases only after explicit
invocation, one issue at a time, and must stop on any red or ambiguous gate. Evolution stays in
`/idd-evolve`. Prefer repository-native tests and git/PR history.

## Editing discipline

- Keep `skills/idd/SKILL.md` ≤60 lines, `skills/idd-plan/SKILL.md` ≤160 lines,
  `skills/idd-issue/SKILL.md` ≤70 lines, `skills/idd-implement/SKILL.md` ≤160,
  `skills/idd-land/SKILL.md` ≤120, `skills/idd-auto/SKILL.md` ≤120, `skills/idd-acceptance/SKILL.md`
  ≤120, `skills/idd-publish/SKILL.md` ≤120, and `skills/idd-evolve/SKILL.md` ≤80.
- Keep every line of `skills/*/SKILL.md`, `CONSTITUTION.md`, and this file at or under 100
  characters, counted in characters: fold a long front-matter scalar with `>-`, rewrap prose at 100
  columns, and compress a file that would then exceed its line cap rather than raise the cap.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Kept evolve changes reach `main` only through a PR opened by `scripts/propose.sh` on
  `evolve/<slug>` and squash-merged by `scripts/land-evolution.sh` on the maintainer's explicit
  instruction after review; `scripts/protect-main.sh` keeps GitHub enforcing that. Only explicit
  `/idd-land` or `/idd-auto` authority, or `/idd-publish` authority for its one preparation PR, may
  merge a project PR; nothing may force-push.

## Naming conventions

Adopted 2026-09-03. Cite the rule IDs in issues and review comments.

- **Issue title (N-1).** Imperative outcome, sentence case. No type prefix, no trailing period, no
  issue number, no requirement/slice ID. Say what is true when the issue closes, not only the
  symptom. One coherent outcome per issue — a conjunction alone is not a reason to split; split only
  when the joined parts are independently deliverable and verifiable. This is a review rule, not a
  mechanical grammar.
- **PR title (N-2).** Character-identical to the issue it delivers. If the wording is wrong, edit
  the issue first, then match it.
- **Branch (N-3).** `issue/<issue-number>-<lowercase-kebab-slug>`, matching
  `^issue/[1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*$`. The slug is a handle, not the title. An evolution of
  this repository has no issue: it uses `evolve/<lowercase-kebab-slug>`, and because the squash
  merge takes both from the PR, its PR title is the N-4 commit subject and its PR body the commit
  body.
- **Commit subject (N-4).** `<type>(<scope>)?: <lowercase imperative>`, at most 72 authored
  characters — a provider-added trailing ` (#N)` sits outside that budget. Scope is one kebab-case
  identifier: no spaces, no colon, one scope only. Evidence, rationale and measurements belong in
  the body, never the subject. Types: `feat` `fix` `docs` `test` `refactor` `perf` `chore` `build`
  `ci` `evolve`
- **Landed subject.** A squash merge derives its subject from the untyped N-2 PR title, so the PR
  declares the type instead, in exactly one body line: `Delivery-Type: <type>`. `/idd-implement`
  writes it when opening the PR and `skills/idd-land/scripts/land.sh` composes `<type>: <issue
  title, initial letter lowercased> (#<PR>)` and passes it as `--subject`; landing stops on an
  absent, repeated, non-lowercase, or unlisted type and never truncates an over-72 subject. Do not
  "fix" a subject by putting a type prefix on the PR title — that breaks N-2 instead.
- **Private material.** This repository is public. Never name the private companion product-contract
  repository (this project's `{project}-prd` sibling), one of its documents, or one of its sections
  in a branch, commit, issue, or PR — not even in order to say what must not be named. A requirement
  or slice identifier (`R-###`, `S-###`, `SLICE-###`, `FR-###`, `NFR-###`) is forbidden only where
  it is defined *solely* in that companion. `R-###`/`S-###` are defined only there, so they never
  belong on any surface in this repository. Never rely on a history rewrite as cleanup — commits
  survive in provider-retained PR refs, and issue/PR text is provider metadata outside git entirely.
- **Labels.** None by default. Add one only when a repository template requires it or it names a
  partition someone actually queries; a label applied uniformly to every issue partitions nothing.
