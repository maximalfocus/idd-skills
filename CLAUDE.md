# idd-skills repository conventions

## Sources of truth

Author `/idd`, `/idd-plan`, `/idd-issue`, `/idd-implement`, `/idd-land`, `/idd-auto`,
`/idd-acceptance`, `/idd-promote`, `/idd-publish`, and `/idd-evolve` in their matching
`skills/*/SKILL.md` sources. `CONSTITUTION.md` governs methodology changes. Do not create a
`commands/` mirror; Claude Code, Codex, Pi, and OpenCode consume the same Agent Skills sources
through symlinks created by `scripts/install.sh` (OpenCode discovers the shared `~/.agents/skills/`
links). Keep skill inputs portable: runners that do not inject `$ARGUMENTS` must be able to use the
user's request.

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
invocation, one issue at a time, and must stop on any red or ambiguous gate. `/idd-promote` alone
moves an implementation repository's `dev` into its release branch `main`, on explicit invocation.
Evolution stays in `/idd-evolve`. Prefer repository-native tests and git/PR history.

## Editing discipline

- Keep `skills/idd/SKILL.md` ≤60 lines, `skills/idd-plan/SKILL.md` ≤160 lines,
  `skills/idd-issue/SKILL.md` ≤70 lines, `skills/idd-implement/SKILL.md` ≤160,
  `skills/idd-land/SKILL.md` ≤120, `skills/idd-auto/SKILL.md` ≤120, `skills/idd-acceptance/SKILL.md`
  ≤120, `skills/idd-publish/SKILL.md` ≤120, `skills/idd-promote/SKILL.md` ≤60, and
  `skills/idd-evolve/SKILL.md` ≤80.
- Keep every line of `skills/*/SKILL.md`, `CONSTITUTION.md`, and this file at or under 100
  characters, counted in characters: fold a long front-matter scalar with `>-`, rewrap prose at 100
  columns, and compress a file that would then exceed its line cap rather than raise the cap.
- Every other line a change adds — scripts, tests, README — follows the shared line width in
  `skills/idd-plan/references/conventions.md`; `scripts/propose.sh` refuses a wider one.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Kept evolve changes reach `main` only through a PR opened by `scripts/propose.sh` on
  `evolve/<slug>` and squash-merged by `scripts/land-evolution.sh` on the maintainer's explicit
  instruction after review; `scripts/protect-main.sh` keeps GitHub enforcing that. Only explicit
  `/idd-land` or `/idd-auto` authority, or `/idd-publish` authority for its one preparation PR, may
  merge a project PR; a PRD's `progress/` batch PR merges only at a milestone reconcile under that
  authority or a direct `/idd-plan --reconcile`; nothing may force-push.

## Branch strategy

This methodology repository stays single-branch on `main` (Constitution Article 6); the line below
keeps `protect-main.sh ensure` from integrating it on `dev`:

Integration-branch: main

## Naming conventions

Adopted 2026-09-03 and shared since by every repository IDD manages:
`skills/idd-plan/references/conventions.md` is their single source — N-1 issue title, N-2 PR title,
N-3 branch, N-4 commit subject, the landed `Delivery-Type` subject, labels, the default-branch
rule, and the 100-character line width. Cite the rule IDs in issues and review comments. In this
repository:

- An evolution has no issue: it uses `evolve/<lowercase-kebab-slug>`, and because the squash merge
  takes both from the PR, its PR title is the N-4 commit subject and its PR body the commit body.
- `/idd-implement` writes the `Delivery-Type` line when opening the PR and
  `skills/idd-land/scripts/land.sh` composes the landed subject from it and passes it as
  `--subject`. Do not "fix" a subject by putting a type prefix on the PR title — that breaks N-2.
- **Private material.** This repository is public. Never name the private companion product-contract
  repository (this project's `{project}-prd` sibling), one of its documents, or one of its sections
  in a branch, commit, issue, or PR — not even in order to say what must not be named. A requirement
  or slice identifier (`R-###`, `S-###`, `SLICE-###`, `FR-###`, `NFR-###`) is forbidden only where
  it is defined *solely* in that companion. `R-###`/`S-###` are defined only there, so they never
  belong on any surface in this repository. Never rely on a history rewrite as cleanup — commits
  survive in provider-retained PR refs, and issue/PR text is provider metadata outside git entirely.
