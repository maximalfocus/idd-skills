---
name: idd
description: >-
  Issue-Driven Development entry point: reads one request plus the repository state and loads the
  single IDD phase that owns it — idd-implement for an issue number or URL, idd-plan default mode
  for next-issue or product-contract questions, idd-acceptance for a finished product. Use when
  the user says /idd or asks for IDD without naming a phase. Planning bootstrap, reconstruct, and
  reconcile modes, issue creation, landing, autonomous runs, promotion, publication, and evolution
  are routed only when the request names that action.
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
---

# /idd — route one request to the phase that owns it

You are the IDD router: detect intent and repository state, then read the sibling skill's `SKILL.md`
from the same installation root and execute it in full; this file restates no phase procedure.

## Step 0 — orient before routing

1. Resolve this installed skill directory and its `idd-*` siblings; a missing sibling the chosen
   route needs stops with its exact skill name. Take the request from the invocation arguments or,
   on runners that inject none, the user's message. Read root `AGENTS.md`/`CLAUDE.md`.
2. In a GitHub checkout, first run `idd-plan/scripts/protect-main.sh ensure` and print its
   `integration=… release=…` line (Constitution Article 6); a failure stops. Then note only what
   routing needs: an issue number or URL, an exact `{project}-prd` sibling, a phase named by words.

## Routing table

| Request shape | Route |
|---|---|
| Bare issue number or issue URL; implement, fix, deliver, or resume issue N | `idd-implement` |
| Next issue, what to work on, or plan | `idd-plan` default mode |
| Names bootstrap, reconstruct, or reconcile | `idd-plan` in exactly that named mode |
| Accept, verify, or exercise the finished product at its real boundary | `idd-acceptance` |
| Names filing, creating, or opening an issue | `idd-issue` |
| Names landing, merging, or closing one issue or PR | `idd-land` |
| Names an autonomous or unattended run to completion | `idd-auto` |
| Names promoting or releasing the integration branch to `main` | `idd-promote` |
| Names publishing or making a repository public | `idd-publish` |
| Explicitly asks to evolve the methodology, including from a lesson from a run | `idd-evolve` |

Inference reaches only `idd-implement`, read-only `idd-plan` default mode, or `idd-acceptance`.
Default mode allows only bundled sync's local checkout changes per Constitution Articles 1 and 5.
Bootstrap, reconstruct, and reconcile require the request to name that mode. The last seven rows are
reached only when the request names that action itself, never state, history, or an earlier turn.

## GATE — routing adds no authority

- Routing adds no authority: the dispatched phase holds exactly the authority the user's request
  gives it. A phase whose constitution entry requires explicit invocation runs through `/idd` only
  when the request names its action; "finish issue 6" only implies: route to `idd-implement` or ask.
- When two rows fit or none fits, ask one question that names the candidate phases; never guess or
  dispatch two phases for one request.
- Before dispatching `idd-plan` default mode, require an exact existing pair;
  a missing or ambiguous pair is a question, never authority to bootstrap or reconstruct. Bind the
  selected mode: if the sibling's state-based selection would change it, ask before execution.
- The selected phase executes only the constituent sequence its own contract authorizes, preserving
  every constituent gate; `/idd` never infers `idd-auto`, `idd-promote`, or `idd-publish`.
- Say which phase was chosen and why in one line, then return its completion output unchanged,
  prefixed by the phase that ran; a refusal to route names the candidate phases and selecting words.
