# idd-skills

Lightweight Issue-Driven Development for greenfield and existing software repositories.

`/idd-plan` can bootstrap a private `{project}-prd` containing a concise PRD and progress tracker, choose one next issue from an existing convention-linked pair, or reconcile verified progress; `/idd-issue` creates that implementation-ready GitHub issue; `/idd` takes it through focused implementation, repository-native verification, commit, push, and a linked PR. It deliberately does **not** create plan files, golden-file suites, trace artifacts, or per-wave reviews.

Normal lifecycle: `/idd-plan` → `/idd-issue` → `/idd` → optional `/peerreview` → `/idd-land`. Landing automatically commits verified lifecycle progress to the associated PRD repository; `/idd-plan --reconcile` exists only for repair or explicit resynchronization.

## Skill

| Skill | Purpose |
|---|---|
| `/idd-plan [project-name\|--reconcile]` | Bootstrap a private product contract, recommend one next issue, or repair its tracker |
| `/idd-issue <request> [--repo OWNER/REPO]` | Create one evidence-backed, duplicate-checked GitHub issue |
| `/idd <issue-number-or-url>` | Implement one well-scoped issue and open a PR; never auto-merge or deploy |
| `/idd-land <issue-number-or-url> [--pr N] [--accept-residuals]` | Validate and squash-merge one PR, close its issue, then delete its branches |
| `/idd-evolve [post-plan\|post-create\|post-issue\|simplify]` | Filter proven run lessons into IDD; rejected candidates leave no log |

The workflow was initially derived from implementing [Reporting-Platform issue #6](https://github.com/yubin-[removed]/Reporting-Platform/issues/6): live issue/comments as intent, a clean issue branch, exhaustive entry-point search, repository-native tests, explicit separation of introduced versus baseline failures, and smoke-testing the built runtime boundary. Its first evolve pass absorbed an implementation-proven runtime-flag gap: verify precedence, invalid values, unsupported profiles, and baked behavior when startup hooks are bypassed.

## Install

```sh
bash scripts/install.sh
```

This symlinks all portable Agent Skills sources into `~/.agents/skills/`, `~/.claude/skills/`, and `${CODEX_HOME:-~/.codex}/skills/`. OpenCode discovers the `~/.agents/skills/` installation natively, so the installer deliberately does not create a duplicate under `~/.config/opencode/skills/`.

| Runner | Invoke |
|---|---|
| Claude Code | `/idd-plan` · `/idd-issue fix the timeout` · `/idd 6` · `/idd-land 6` |
| Codex | `$idd-plan` · `$idd-issue fix the timeout` · `$idd 6` · `$idd-land 6` |
| Pi | `/skill:idd-plan` · `/skill:idd-issue fix the timeout` · `/skill:idd 6` · `/skill:idd-land 6` |
| OpenCode | `Use idd-plan to choose the next issue` · `Use idd-issue to file it` · `Use idd for issue 6` · `Use idd-land for issue 6` |

The same runner-specific forms apply to `idd-evolve`. Restart an already-running harness after installation so it rescans skills.

## Layout

- `skills/idd-plan/SKILL.md` — greenfield product-contract bootstrap, next-issue planning, and reconciliation
- `skills/idd-issue/SKILL.md` — evidence-backed issue creation workflow
- `skills/idd/SKILL.md` — issue implementation workflow
- `skills/idd-land/SKILL.md` — explicit landing workflow
- `skills/idd-evolve/SKILL.md` — pass-or-nothing evolution workflow
- `CONSTITUTION.md` — evolution law and size gates
- `scripts/install.sh` — cross-runner symlink installer
- `scripts/resolve-prd-pair.sh` — deterministic `{project}` ↔ `{project}-prd` association
- `scripts/init-prd.sh` — validate, commit, and privately publish an approved greenfield PRD/tracker
- `scripts/land.sh` — deterministic squash/close/branch-cleanup lifecycle
- `scripts/test-land.sh` — isolated mock lifecycle + idempotency test
- `scripts/validate.sh` — structural and lifecycle validation
