# idd-skills

Lightweight Issue-Driven Development for greenfield and existing software repositories.

`/idd-plan` can bootstrap a private `{project}-prd` containing a concise PRD and progress tracker — from requirements for a new product, or reconstructed from an already-implemented repository — choose one next issue from an existing convention-linked pair, or reconcile verified progress; `/idd-issue` creates that implementation-ready GitHub issue; `/idd` takes it through focused implementation, repository-native verification, commit, push, and a linked PR. `/idd-auto` can explicitly orchestrate those same current gates one issue at a time until the PRD implementation scope is complete. `/idd-acceptance` exercises the final real product boundary, and `/idd-publish` can explicitly prepare and publish only the implementation repository while its companion contract remains private. IDD deliberately does **not** create plan files, golden-file suites, trace artifacts, or per-wave reviews.

Normal lifecycle: `/idd-plan` → `/idd-issue` → `/idd` → optional `/peerreview` → `/idd-land` → `/idd-acceptance` → optional `/idd-publish`. Landing automatically commits verified lifecycle progress to the associated PRD repository; `/idd-plan --reconcile` exists only for repair or explicit resynchronization. Publication is a separate explicit visibility operation, never an implicit consequence of implementation or acceptance.

Autonomous lifecycle: `/idd-auto <project-name-or-path>`. One explicit invocation repeatedly selects, creates, implements, verifies, lands, and reconciles one issue at a time. It stops rather than bypassing ambiguity, residual acceptance, red CI/reviews, external prerequisites, or material product decisions.

Across both lifecycles, IDD treats the PRD as one coherent design contract and preserves its conceptual model over a cheap one-off change. New concepts, special cases, or fragmenting convenience features require an explicit recorded design decision; final acceptance verifies that the integrated product fits the model at its real boundary.

## Skill

| Skill | Purpose |
|---|---|
| `/idd-plan [project-name\|--reconstruct\|--reconcile]` | Bootstrap a private product contract from requirements or implemented source, recommend one next issue, or repair its tracker |
| `/idd-issue <request> [--repo OWNER/REPO]` | Create one evidence-backed, duplicate-checked GitHub issue |
| `/idd <issue-number-or-url>` | Implement one well-scoped issue and open a PR; never auto-merge or deploy |
| `/idd-land <issue-number-or-url> [--pr N] [--accept-residuals]` | Validate and squash-merge one PR, close its issue, then delete its branches |
| `/idd-auto <project-name-or-path>` | Sequentially finish an exact PRD-linked project through the existing gated lifecycle |
| `/idd-evolve [post-plan\|post-create\|post-issue\|simplify]` | Filter proven run lessons into IDD; rejected candidates leave no log |
| `/idd-acceptance <project-name-or-path>` | Exercise the completed product at its real CLI, API, browser, service, container, or migration boundary |
| `/idd-publish <project-name-or-path>` | Prepare one private pair, audit every public surface, and make only the implementation repository public |

The workflow was initially derived from a production implementation issue: live issue/comments as intent, a clean issue branch, exhaustive entry-point search, repository-native tests, explicit separation of introduced versus baseline failures, and smoke-testing the built runtime boundary. Its first evolve pass absorbed an implementation-proven runtime-flag gap: verify precedence, invalid values, unsupported profiles, and baked behavior when startup hooks are bypassed.

## Install

Install the complete suite with the cross-agent Skills CLI:

```sh
npx skills add maximalfocus/idd-skills --skill '*'
```

Add `-g` for a user-wide installation or `-a codex -a claude-code -a opencode -a pi` to select agents explicitly. The default copied installation is self-contained and remains usable after the downloaded source or temporary clone is removed.

Selective install is supported for standalone skills:

```sh
npx skills add maximalfocus/idd-skills --skill idd-issue
```

Composite dependencies must be installed together. `idd-auto` requires `idd-plan`, `idd-issue`, `idd`, `idd-land`, and `idd-acceptance`; `idd-land` and `idd-acceptance` require `idd-plan`; `idd-publish` requires `idd-plan`, `idd-issue`, `idd`, and `idd-land`. Installing the complete suite is the simplest safe choice. `idd-evolve` also requires an explicit or current `idd-skills` methodology checkout because it edits and validates that repository rather than its installed workflow definition.

Development fallback for contributors working from a persistent checkout:

```sh
bash scripts/install.sh
```

This fallback creates absolute symlinks in `~/.agents/skills/`, `~/.claude/skills/`, and `${CODEX_HOME:-~/.codex}/skills/`; moving or deleting the checkout breaks those links. It preflights the complete destination set before mutation and rolls back links created by a failed invocation. OpenCode and Pi discover the shared `~/.agents/skills/` installation natively.

| Runner | Invoke |
|---|---|
| Claude Code | `/idd-plan` · `/idd-issue fix the timeout` · `/idd 6` · `/idd-land 6` · `/idd-auto widget` · `/idd-acceptance widget` · `/idd-publish widget` |
| Codex | `$idd-plan` · `$idd-issue fix the timeout` · `$idd 6` · `$idd-land 6` · `$idd-auto widget` · `$idd-acceptance widget` · `$idd-publish widget` |
| Pi | `/skill:idd-plan` · `/skill:idd-issue fix the timeout` · `/skill:idd 6` · `/skill:idd-land 6` · `/skill:idd-auto widget` · `/skill:idd-acceptance widget` · `/skill:idd-publish widget` |
| OpenCode | `Use idd-plan to choose the next issue` · `Use idd-issue to file it` · `Use idd for issue 6` · `Use idd-land for issue 6` · `Use idd-auto for widget` · `Use idd-acceptance for widget` · `Use idd-publish for widget` |

The same runner-specific forms apply to `idd-evolve`. Restart an already-running harness after installation so it rescans skills.

## Publication boundary

`idd-publish` is user-invoked and fail-closed. It first lands one normal preparation issue while both repositories are private, requires a license and green installation/runtime evidence, scans all reachable Git history and retained provider surfaces for secrets or private identities, and only then changes the implementation repository to public. The convention-linked product contract remains private. Publication does not deploy, host, create a release, or publish a registry package.

## Layout

- `skills/idd-plan/SKILL.md` — greenfield and reconstructed product-contract bootstrap, next-issue planning, and reconciliation
- `skills/idd-issue/SKILL.md` — evidence-backed issue creation workflow
- `skills/idd/SKILL.md` — issue implementation workflow
- `skills/idd-land/SKILL.md` — explicit landing workflow
- `skills/idd-auto/SKILL.md` — autonomous one-issue-at-a-time PRD completion loop
- `skills/idd-evolve/SKILL.md` — pass-or-nothing evolution workflow
- `skills/idd-acceptance/SKILL.md` — final integrated user-boundary acceptance workflow
- `skills/idd-publish/SKILL.md` — fail-closed implementation-repository publication workflow
- `CONSTITUTION.md` — evolution law and size gates
- `skills/*/scripts/` — runtime resources bundled with the skills that own them
- `scripts/install.sh` — development-only cross-runner symlink installer
- `scripts/test-install.sh` — isolated preflight, rollback, clean-install, and idempotency regression gate
- `scripts/resolve-prd-pair.sh`, `scripts/init-prd.sh`, `scripts/land.sh`, `scripts/tracker-gate.sh`, `scripts/manifest.sh`, `scripts/prd-fold-gate.sh` — checkout compatibility wrappers for bundled scripts
- `scripts/test-land.sh` — isolated mock lifecycle, idempotency, and rewritten-source test
- `scripts/test-tracker-gate.sh`, `scripts/test-manifest.sh`, `scripts/test-prd-fold-gate.sh`, `scripts/test-static-gate.sh` — isolated tests for the tracker gate, the preserved-artifact manifest tooling, the PRD fold gate, and the acceptance static gate
- `scripts/scan-exposure.sh`, `scripts/test-scan-exposure.sh` — checkout wrappers for the bundled publication scan and tests
- `scripts/test-portable-install.sh` — isolated standard-copy and installed-runtime regression gate
- `scripts/validate.sh` — structural and lifecycle validation

## License

MIT. See [LICENSE](LICENSE).
