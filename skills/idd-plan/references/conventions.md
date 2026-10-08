# IDD repository conventions

One convention set for every repository IDD manages: the methodology repository, each
implementation repository, and its `{project}-prd`. Bundled scripts enforce the mechanical parts
and name the rule they refuse; the rest is review. Cite the rule IDs in issues and review comments.

## Naming

- **Issue title (N-1).** Imperative outcome, sentence case. No type prefix, no trailing period, no
  issue number, no requirement/slice ID. Say what is true when the issue closes, not only the
  symptom. One coherent outcome per issue — a conjunction alone is not a reason to split; split only
  when the joined parts are independently deliverable and verifiable. This is a review rule, not a
  mechanical grammar.
- **PR title (N-2).** Character-identical to the issue it delivers. If the wording is wrong, edit
  the issue first, then match it. A pull request with no issue — a tracker batch, a contract change,
  or an evolution — is titled with its N-4 commit subject instead.
- **Branch (N-3).** One lowercase kebab-case form per kind of change: `issue/<issue-number>-<slug>`
  delivers an issue, `progress/batch` carries a `{project}-prd` tracker batch, `prd/<slug>` changes
  a product contract, and `evolve/<slug>` evolves a methodology repository. The slug is a handle,
  not the title. `dev` is an implementation repository's long-lived integration branch and the head
  of its promotion pull request, titled `chore(release): promote dev to main`.
- **Commit subject (N-4).** `<type>(<scope>)?: <lowercase imperative>`, at most 72 authored
  characters — a provider-added trailing ` (#N)` sits outside that budget. Scope is one kebab-case
  identifier: no spaces, no colon, one scope only. Evidence, rationale and measurements belong in
  the body, never the subject. Types: `feat` `fix` `docs` `test` `refactor` `perf` `chore` `build`
  `ci` `evolve`. A `{project}-prd` commits tracker changes as `docs(progress): …` and contract
  changes as `docs(prd): …`.
- **Landed subject.** An issue's squash subject would come from its untyped N-2 title, so its pull
  request declares the type in exactly one body line, `Delivery-Type: <type>`, and landing composes
  `<type>: <issue title, initial letter lowercased unless it opens an initialism> (#<PR>)`; it stops
  on an absent, repeated, or unlisted type and never truncates an over-72 subject. Do not "fix" a
  subject by type-prefixing the PR title: that breaks N-2. An issue-less pull request lands as its
  title followed by ` (#<PR>)`.
- **Labels.** None by default. Add one only when a repository template requires it or it names a
  partition someone actually queries, such as a partitioned contract's context; a label applied
  uniformly to every issue partitions nothing.

## Default branch

The default branch changes only through a squash-merged pull request, and nothing force-pushes.
Bootstrap pushes a new repository's single initial commit; every later change goes through a
reviewed pull request. That is practice, not enforcement: the user's repositories have no branch
protection (their decision, 2026-10-07), so no step applies, checks, or suggests it.

An implementation repository integrates on `dev`: bootstrap pushes the initial commit to `main`,
creates `dev` from it, and makes `dev` the default branch, so every issue pull request targets and
squash-merges into `dev` and `Closes #N` still closes on merge. `main` is the release branch: it
changes only through a merge-commit pull request from `dev`, opened and merged by the explicit,
optional `/idd-promote`; a squash or rebase there would make `main` diverge from `dev`.
`/idd`, `/idd-implement`, `/idd-land`, and `/idd-auto` start with `integration-branch.sh ensure`,
which prints `integration=<branch> release=<main|none>`. It creates `dev` from `main` regardless of
`main`'s history and makes it the default (allowing the merge commits promotion needs). Every run
retargets open main-based PRs except the promotion PR and switches a clean checkout on `main` to
`dev`, so a retry completes partial adoption. A root `AGENTS.md` or `CLAUDE.md` line opts out and
keeps `main` the single default branch:

```
Integration-branch: main
```

A `{project}-prd` never integrates on `dev`; its tracker and contract changes merge to `main`.

## Line width

No change adds a line over 100 characters to a tracked text file — prose, code, and configuration
alike; characters are counted, not bytes, and the count never depends on the locale: a valid UTF-8
sequence counts once and every byte outside one counts once. A Markdown table row is exempt: it is
one line that cannot be rewrapped, so its cells answer to their own budgets, such as the tracker
gate's per-cell word budget in `PROGRESS.md`, rather than to the width. A path listed on the
repository's `Formatter-owned:` line in `AGENTS.md` or `CLAUDE.md` takes the width its tool gives it
instead: a language formatter at the width the repository configures and checks, or a generator,
package manager, or recorder whose output nobody lays out by hand. The line lists backticked
positive Git pathspec patterns (including paths with spaces) and may continue on lines holding only
backticked patterns. Exclude pathspecs are refused; use explicit positive patterns for the files the
tool owns:

```
Formatter-owned: `*.py` `*.go` `package-lock.json` `tests/fixtures/`
```

The bundled `idd-plan/scripts/line-width.sh check <base> [<rev>|--cached]` is the gate: landing,
tracker batches, and evolution proposals run it. Only added lines count, so a change never inherits
the debt of lines it leaves alone. With no revision it measures the change in hand — the working
tree while it is dirty, untracked files included — so running it before committing or staging
cannot pass on the previous commit.

## Adopting an existing repository

A repository created before these conventions adopts them from its next change; nothing rewrites
its history or its legacy lines. The first IDD flow in an implementation repository that has not
opted out runs `ensure`, which integrates it on `dev`. Before landing:

1. **Formatter-owned paths.** Before the first landing that adds formatter-laid lines over 100
   characters, declare those paths in a reviewed change to `AGENTS.md` or `CLAUDE.md`. A `Types:`
   line binds nothing any more and may go in the same change.
2. **Open pull requests.** Retitle each to its issue title (N-2) and declare an N-4
   `Delivery-Type`. One whose head is not `issue/<N>-<slug>` (N-3) is replaced: push the same
   commits to that branch, open a pull request from it, and close the old one.

An open `{project}-prd` progress batch whose commits still read `progress:` merges as it stands; its
next tracker commit uses `docs(progress):`.
