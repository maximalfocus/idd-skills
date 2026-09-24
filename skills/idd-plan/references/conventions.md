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
Bootstrap pushes a new repository's single initial commit, then runs the bundled
`idd-plan/scripts/protect-main.sh apply`: pull request required, squash only with the PR title and
body as the commit, linear history, no force-push, no deletion, no bypass. GitHub Free enforces
that ruleset only on a public repository, so a private one keeps the settings plus branch and pull
request discipline, and becoming public requires rerunning `apply`. Landing runs `verify` and
stops on drift.

An implementation repository integrates on `dev`: bootstrap pushes the initial commit to `main`,
creates `dev` from it, and makes `dev` the default branch, so every issue pull request targets and
squash-merges into `dev` and `Closes #N` still closes on merge. `main` is the release branch: a
second ruleset lets it change only through a merge-commit pull request from `dev`, opened and merged
by the explicit, optional `/idd-promote`; a squash or rebase there would make `main` diverge from
`dev`. `protect-main.sh ensure` begins every IDD flow and prints `integration=<branch>
release=<main|none>`. In a repository not yet integrated it creates `dev` from `main` whatever
`main`'s history, makes it the default, retargets open pull requests from `main`, applies both
rulesets, and switches a clean checkout on `main` to `dev`. A root `AGENTS.md` or `CLAUDE.md` line
opts out and keeps `main` the single default branch:

```
Integration-branch: main
```

A `{project}-prd` never integrates on `dev`; its tracker and contract changes merge to `main`.

## Line width

No change adds a line over 100 characters to a tracked text file — prose, code, and configuration
alike; characters are counted, not bytes. A Markdown table row is exempt: it is one line that cannot
be rewrapped, so its cells answer to their own budgets, such as the tracker gate's per-cell word
budget in `PROGRESS.md`, rather than to the width. A path listed on the repository's
`Formatter-owned:` line in `AGENTS.md` or `CLAUDE.md` takes the width its tool gives it instead: a
language formatter at the width the repository configures and checks, or a generator, package
manager, or recorder whose output nobody lays out by hand. The line lists git pathspec patterns and
may continue on lines holding only backticked patterns:

```
Formatter-owned: `*.py` `*.go` `package-lock.json` `tests/fixtures/`
```

The bundled `idd-plan/scripts/line-width.sh check <base> [<rev>|--cached]` is the gate: landing,
tracker batches, and evolution proposals run it. Only added lines count, so a change never inherits
the debt of lines it leaves alone. With no revision it measures the change in hand — the working
tree while it is dirty — so running it before committing cannot pass on the previous commit.

## Adopting an existing repository

A repository created before these conventions adopts them from its next change; nothing rewrites
its history or its legacy lines. Landing stops before any mutation until adoption is complete:

1. **Protection.** `apply` changes repository settings, so it runs once per repository on the
   user's explicit instruction, never as a landing repair: run the bundled
   `idd-plan/scripts/protect-main.sh apply <owner>/<repo>` for the implementation repository and
   its `{project}-prd`, then `verify` each. The exception is integration: the first IDD flow in an
   implementation repository that has not opted out runs `ensure`, which applies both rulesets.
2. **Formatter-owned paths.** Before the first landing that adds formatter-laid lines over 100
   characters, declare those paths in a reviewed change to `AGENTS.md` or `CLAUDE.md`. A `Types:`
   line binds nothing any more and may go in the same change.
3. **Open pull requests.** Retitle each to its issue title (N-2) and declare an N-4
   `Delivery-Type`. One whose head is not `issue/<N>-<slug>` (N-3) is replaced: push the same
   commits to that branch, open a pull request from it, and close the old one.

An open `{project}-prd` progress batch whose commits still read `progress:` merges as it stands; its
next tracker commit uses `docs(progress):`.
