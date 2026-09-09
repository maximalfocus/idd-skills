---
name: idd
description: "Issue-Driven Development entry point: reads one request plus the repository state and loads the single IDD phase that owns it — idd-implement for an issue number or URL, idd-plan default mode for next-issue or product-contract questions, idd-acceptance for a finished product. Use when the user says /idd or asks for IDD without naming a phase. Planning bootstrap, reconstruct, and reconcile modes, issue creation, landing, autonomous runs, publication, and evolution are routed only when the request names that action."
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
| Next issue, what to work on, or plan; explicitly requested bootstrap, reconstruct, or reconcile | `idd-plan` default mode unless the request explicitly names another mode |
| Accept, verify, or exercise the finished product at its real boundary | `idd-acceptance` |
| Names filing, creating, or opening an issue | `idd-issue` |
| Names landing, merging, or closing one issue or PR | `idd-land` |
| Names an autonomous or unattended run to completion | `idd-auto` |
| Names publishing or making a repository public | `idd-publish` |
| Explicitly asks to evolve the methodology, including from a lesson from a run | `idd-evolve` |

Inference reaches only `idd-implement`, read-only `idd-plan` default mode, or `idd-acceptance`. Bootstrap, reconstruct, and reconcile require the request to name that mode. The last five rows are reached only when the request names that action itself; state, history, or an earlier turn never stands in for the words.

## GATE — routing adds no authority

- Routing adds no authority: the dispatched phase holds exactly the authority the user's request gives it and no more. A phase whose constitution entry requires explicit invocation runs through `/idd` only when the request names its action; a request that merely implies it (for example "finish issue 6") routes to `idd-implement`, or asks.
- When two rows fit or none fits, ask one question that names the candidate phases. Never guess, and never dispatch two phases for one request.
- Before dispatching `idd-plan` default mode, require an exact existing pair; a missing or ambiguous pair is a question, never authority to bootstrap or reconstruct. Bind the selected mode: if the sibling's state-based selection would change it, ask before execution.
- One request, one routed phase. The selected phase may execute only the constituent sequence its own contract authorizes, preserving every constituent gate; `/idd` never starts `idd-auto` or `idd-publish` by inference.
- Say in one line which phase was chosen and why before executing it, so the dispatch is auditable in the transcript.

## Completion

Return the routed phase's completion output unchanged, prefixed by the phase that ran. A refusal to route reports the candidate phases and the words that would select one.
