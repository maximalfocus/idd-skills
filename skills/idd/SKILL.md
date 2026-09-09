---
name: idd
description: "Issue-Driven Development entry point: reads one request plus the repository state and loads the single IDD phase that owns it — idd-implement for an issue number or URL, idd-plan for next-issue or product-contract questions, idd-acceptance for a finished product. Use when the user says /idd or asks for IDD without naming a phase. Issue creation, landing, autonomous runs, publication, and evolution are routed only when the request names that action."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd — route one request to the phase that owns it

You are the IDD router. Detect the user's intent and the repository state, then read the sibling skill's `SKILL.md` from the same installation root and execute it in full. This file owns routing only; it restates no phase procedure and adds none.

## Step 0 — orient before routing

1. Resolve this installed skill directory and its siblings `idd-implement`, `idd-plan`, `idd-issue`, `idd-land`, `idd-auto`, `idd-acceptance`, `idd-publish`, and `idd-evolve`. A missing sibling that the chosen route needs stops with its exact skill name.
2. Take the request from the invocation arguments or, on runners that do not inject arguments into skills, from the user's message. Read root `AGENTS.md`/`CLAUDE.md`.
3. Note only what routing needs: whether the checkout is a git repository, whether the request carries an issue number or GitHub issue URL, whether an exact `{project}-prd` sibling exists, and whether the request names a phase in its own words.

## Routing table

| Request shape | Route |
|---|---|
| Bare issue number or issue URL; implement, fix, deliver, or resume issue N | `idd-implement` |
| Next issue, what to work on, plan; bootstrap, reconstruct, or reconcile a product contract | `idd-plan` in the mode the request names |
| Accept, verify, or exercise the finished product at its real boundary | `idd-acceptance` |
| Names filing, creating, or opening an issue | `idd-issue` |
| Names landing, merging, or closing one issue or PR | `idd-land` |
| Names an autonomous or unattended run to completion | `idd-auto` |
| Names publishing or making a repository public | `idd-publish` |
| Names evolving the methodology or a lesson from a run | `idd-evolve` |

The first three rows may be reached by inference. The last five are reached only when the request names that action itself; state, history, or an earlier turn never stands in for the words.

## GATE — routing adds no authority

- Routing adds no authority: the dispatched phase holds exactly the authority the user's request gives it and no more. A phase whose constitution entry requires explicit invocation runs through `/idd` only when the request names its action; a request that merely implies it (for example "finish issue 6") routes to the non-destructive phase, or asks.
- When two rows fit or none fits, ask one question that names the candidate phases. Never guess, and never run two phases for one request.
- One request, one phase. Chaining phases is `idd-auto`'s job and needs its own explicit invocation; `/idd` never starts it by inference.
- Say in one line which phase was chosen and why before executing it, so the dispatch is auditable in the transcript.

## Completion

Return the routed phase's completion output unchanged, prefixed by the phase that ran. A refusal to route reports the candidate phases and the words that would select one.
