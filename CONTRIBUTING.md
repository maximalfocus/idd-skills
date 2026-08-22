# Contributing to idd-skills

This is the guide for **changing** idd-skills. To understand what idd-skills does, read `README.md`; to understand the rules it lives under, read `CONSTITUTION.md`. This file answers one question: **how do I decide the right way to make a change?**

## First — decide: is it a capability or a lesson?

Ask one question:

> **Does idd-skills need to be able to do something new, or did you hit a problem while using it?**

- **Capability** — idd-skills should *be able to do a thing* (it has an observable acceptance result). Adding a feature, a new command, a new gate, or a new guarantee.
- **Lesson** — you *used* idd-skills and found friction, a gap, a repeated mistake, or something that should behave better.

Pick the path that matches, and don't mix them.

## Capability → product path

Add the capability through the normal product lifecycle:

1. Update the private companion product contract (`{project}-prd`) — add one requirement (`R-###`) and one delivery slice, and update its progress tracker.
2. Drive it through `idd-issue` → `idd` → `idd-land`.

The change must satisfy both the product contract slice **and** every constitutional rule (size caps, lightweight boundary, safety gates).

### Example of a capability

> "idd-skills should verify that a delivered product keeps conceptual integrity — that the product contract is one coherent design contract and that acceptance checks the whole, not just each room."

This is a **capability** because it has an observable acceptance: the contract is coherent, and final acceptance verifies the whole model. It is delivered as a requirement (R-013) by updating the product contract, then the normal lifecycle.

## Lesson → evolution path

Evolve the method directly through `/idd-evolve`:

- It is evidence-driven and **pass-or-nothing**: a reproduced mechanical defect can be proved once; a behavioral rule usually needs multiple independent runs.
- Kept lessons edit `skills/*` and `CONSTITUTION.md` and reach git; rejected lessons leave no log.
- It is a **filter, not an accumulator**: the methodology does not grow a feature list.
- Commit with an `evolve:` (or, for a defect, `fix:`) message.

### Example of a lesson

> "When I ran `/idd` on a project, it silently accepted an unproven acceptance item as a residual. It should stop and name it instead."

This is a **lesson** because it comes from real use and is about how the existing method behaves. You would drive it through `/idd-evolve` with the evidence of that run.

## Red lines

- **Never** add a new feature through `/idd-evolve` — it is a filter, not an accumulator.
- **Never** amend the Constitution through ordinary product planning — a change to a constitutional rule goes through the `/idd-evolve` evidence gate.
- Run `bash scripts/validate.sh` before committing.
- Stage only explicit task-owned paths; never use `git add -A`.
- Never force-push; methodology changes reach `maximalfocus/idd-skills` on `main`.

## Quick reference

| Your idea | Path |
|---|---|
| idd-skills should **do something new** (has an acceptance result) | **Capability** → update the `{project}-prd` contract, then `idd-issue` → `idd` → `idd-land` |
| You **used** it and found a friction / gap / repeated mistake | **Lesson** → `/idd-evolve` |
| You want to change a **constitutional rule** (size cap, evidence bar, boundary, publication discipline) | **Lesson** — goes through the `/idd-evolve` evidence gate |
