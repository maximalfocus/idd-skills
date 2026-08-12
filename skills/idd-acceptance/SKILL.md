---
name: idd-acceptance
description: "Run the final integrated, user-facing acceptance boundary for a completed IDD project and return evidence-backed pass or a classified failure."
compatibility: "Requires the repository's native test/runtime tools; use Playwright, HTTP, CLI, library, container, or migration checks as the product boundary requires."
disable-model-invocation: true
argument-hint: "[project-name|repository-path]"
---

# /idd-acceptance — final integrated acceptance

Use this only after the implementation scope has landed, or when explicitly asked to audit a completed IDD pair. It complements unit, lint, and issue-level checks with a real end-to-end boundary. It never deploys, merges, edits requirements, weakens assertions, or accepts residual failures.

## Orient and bind

1. Resolve the exact `{project}` ↔ `{project}-prd` pair and read `PRD.md`, `PROGRESS.md`, repository instructions, and the final acceptance language. Require clean default branches, no active feature branch, and no open implementation issue or PR. If the pair or completion state is ambiguous, stop with the exact evidence needed to resume.
2. Translate each applicable PRD acceptance outcome into a user-observable journey. Do not invent scenarios or silently mark an outcome not applicable.

## Select the real boundary

- Browser product: use Playwright or the repository's browser runner against the running application; prefer role, label, text, and test-id selectors over CSS classes.
- HTTP/service product: exercise the public API through its real process and dependencies, including authentication and persistence where required.
- CLI or library: run the documented public command/API in a fresh environment and compare pinned, meaningful output; include an invalid-input or safety path when the contract has one.
- Container, worker, or migration product: build/start the real artifact, wait on health/readiness, exercise the observable boundary, and use disposable state.

Unit tests alone are never the final boundary. Run the complete applicable acceptance set against the real product boundary, not a hand-picked happy path.

## Bring up, exercise, and tear down

1. Follow repository instructions and existing acceptance scripts. Prefer Docker Compose healthchecks with `up --wait`; otherwise use explicit readiness probes. Never use fixed sleeps where a state/readiness wait is available.
2. Start from clean or seeded state defined by the PRD. Verify at least one cross-slice journey, restart or fresh-state behavior when relevant, and the required negative/safety behavior.
3. Capture exact commands, commit, environment, readiness evidence, and user-visible assertions. Always tear down temporary services and test data, including on failure.

When a browser suite exists, run `scripts/static-gate.sh <suite-directory>` before execution; it rejects fixed waits and brittle class-based locators.

## Classify failures and gate completion

- **Product:** the shipped behavior violates the PRD; return the failing journey and resume through one normal IDD repair issue.
- **Fixture/data:** the scenario or seed is wrong; repair the fixture without changing the product contract, then rerun.
- **Test/spec:** the assertion or acceptance wording is contradictory or unobservable; stop and request a clarified contract.
- **Environment/tooling:** dependency, credential, port, or readiness failure; report the precise blocker and preserve resumability.

Completion requires every applicable journey to pass, no skipped required outcome, teardown confirmation, and a clean default branch. Report `PASS` or `FAIL` with the boundary, commands, evidence, failure class (if any), and exactly one next action.
