# idd-skills repository conventions

## Sources of truth

Author `/idd-plan`, `/idd-issue`, `/idd`, `/idd-land`, `/idd-auto`, and `/idd-evolve` in their matching `skills/*/SKILL.md` sources. `CONSTITUTION.md` governs methodology changes. Do not create a `commands/` mirror; Claude Code, Codex, Pi, and OpenCode consume the same Agent Skills sources through symlinks created by `scripts/install.sh` (OpenCode discovers the shared `~/.agents/skills/` links). Keep skill inputs portable: runners that do not inject `$ARGUMENTS` must be able to use the user's request.

## Scope

IDD is the lightweight issue workflow. `/idd-plan` may bootstrap only a private PRD plus progress tracker, after product-requirement approval or reconstructed from an implemented repository's source and delivery history; otherwise it consumes an exact convention-linked pair, recommends one next issue, or reconciles verified tracker state. It never creates plan files or issues. `/idd-issue` creates one evidence-backed issue; `/idd` must not absorb CDD's golden-file, trace, mandatory peer-review, acceptance-wave, or deploy machinery. `/idd-land` is the gated merge/closure phase and reconciles an exact associated PRD after landing. `/idd-auto` may sequence those current phases only after explicit invocation, one issue at a time, and must stop on any red or ambiguous gate. Evolution stays in `/idd-evolve`. Prefer repository-native tests and git/PR history.

## Editing discipline

- Keep `skills/idd-plan/SKILL.md` ≤90 lines, `skills/idd-issue/SKILL.md` ≤70 lines, `skills/idd/SKILL.md` ≤160, `skills/idd-land/SKILL.md` ≤120, `skills/idd-auto/SKILL.md` ≤120, and `skills/idd-evolve/SKILL.md` ≤80.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Kept evolve changes commit and push directly to `main`; only explicit `/idd-land` or `/idd-auto` authority may merge a project PR, and neither may force-push.

## Naming conventions

Adopted 2026-09-03. Cite the rule IDs in issues and review comments.

- **Issue title (N-1).** Imperative outcome, sentence case. No type prefix, no
  trailing period, no issue number, no requirement/slice ID. Say what is true
  when the issue closes, not only the symptom. One coherent outcome per issue —
  a conjunction alone is not a reason to split; split only when the joined parts
  are independently deliverable and verifiable. This is a review rule, not a
  mechanical grammar.
- **PR title (N-2).** Character-identical to the issue it delivers. If the
  wording is wrong, edit the issue first, then match it.
- **Branch (N-3).** `issue/<issue-number>-<lowercase-kebab-slug>`, matching
  `^issue/[1-9][0-9]*-[a-z0-9]+(-[a-z0-9]+)*$`. The slug is a handle, not the
  title.
- **Commit subject (N-4).** `<type>(<scope>)?: <lowercase imperative>`, at most
  72 authored characters — a provider-added trailing ` (#N)` sits outside that
  budget. Scope is one kebab-case identifier: no spaces, no colon, one scope
  only. Evidence, rationale and measurements belong in the body, never the
  subject.
  Types: `feat` `fix` `docs` `test` `refactor` `perf` `chore` `build` `ci`
  `evolve`
- **Squash subjects are a known exception, until landing is changed.** `gh pr
  merge --squash` without `--subject` derives the commit subject from the
  untyped N-2 PR title, so N-4 cannot hold for the squash commit today. Until
  landing builds `<type>: <issue title, initial letter lowercased> (#<PR>)` from
  a `Delivery-Type:` field in the PR body, set the squash subject by hand at
  merge time, or accept the untyped one. Do not "fix" it by putting a type
  prefix on the PR title — that breaks N-2 instead.
- **Private material.** This repository is public. Never name the private
  companion product-contract repository (this project's `{project}-prd`
  sibling), one of its documents, or one of its sections in a branch, commit,
  issue, or PR — not even in order to say what must not be named. A requirement
  or slice identifier
  (`R-###`, `S-###`, `SLICE-###`, `FR-###`, `NFR-###`) is forbidden only where
  it is defined *solely* in that companion. `R-###`/`S-###` are defined only
  there, so they never belong on any surface in this repository. Never rely on a
  history rewrite as cleanup — commits survive in provider-retained PR refs, and
  issue/PR text is provider metadata outside git entirely.
- **Labels.** None by default. Add one only when a repository template requires
  it or it names a partition someone actually queries; a label applied uniformly
  to every issue partitions nothing.
