# idd-skills

Lightweight Issue-Driven Development for existing software repositories.

`/idd` takes one open GitHub issue through focused implementation, repository-native verification, commit, push, and a linked PR. It deliberately does **not** create the PRD, golden-file, sibling-repository, trace, or per-wave review artifacts used by CDD.

## Skill

| Skill | Purpose |
|---|---|
| `/idd <issue-number-or-url>` | Implement one well-scoped issue and open a PR; never auto-merge or deploy |

The workflow was initially derived from implementing [Reporting-Platform issue #6](https://github.com/yubin-[removed]/Reporting-Platform/issues/6): live issue/comments as intent, a clean issue branch, exhaustive entry-point search, repository-native tests, explicit separation of introduced versus baseline failures, and smoke-testing the built runtime boundary.

## Install

```sh
bash scripts/install.sh
```

This symlinks the portable Agent Skills source into:

- `~/.agents/skills/idd` — Pi and compatible agents
- `~/.claude/skills/idd` — Claude Code (`/idd`)
- `~/.codex/skills/idd` — Codex

Pi exposes Agent Skills as `/skill:idd` when skill commands are enabled.

## Layout

- `skills/idd/SKILL.md` — single source of truth
- `scripts/install.sh` — cross-runner symlink installer
- `scripts/validate.sh` — structural validation
