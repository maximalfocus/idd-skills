# idd-skills

Lightweight Issue-Driven Development for existing software repositories.

`/idd` takes one open GitHub issue through focused implementation, repository-native verification, commit, push, and a linked PR. It deliberately does **not** create the PRD, golden-file, sibling-repository, trace, or per-wave review artifacts used by CDD.

## Skill

| Skill | Purpose |
|---|---|
| `/idd <issue-number-or-url>` | Implement one well-scoped issue and open a PR; never auto-merge or deploy |
| `/idd-evolve [post-issue\|simplify]` | Filter proven run lessons into IDD; rejected candidates leave no log |

The workflow was initially derived from implementing [Reporting-Platform issue #6](https://github.com/yubin-[removed]/Reporting-Platform/issues/6): live issue/comments as intent, a clean issue branch, exhaustive entry-point search, repository-native tests, explicit separation of introduced versus baseline failures, and smoke-testing the built runtime boundary. Its first evolve pass absorbed an implementation-proven runtime-flag gap: verify precedence, invalid values, unsupported profiles, and baked behavior when startup hooks are bypassed.

## Install

```sh
bash scripts/install.sh
```

This symlinks both portable Agent Skills sources into `~/.agents/skills/`, `~/.claude/skills/`, and `${CODEX_HOME:-~/.codex}/skills/`.

Pi exposes Agent Skills with its `skill:` command prefix when skill commands are enabled.

## Layout

- `skills/idd/SKILL.md` — issue implementation workflow
- `skills/idd-evolve/SKILL.md` — pass-or-nothing evolution workflow
- `CONSTITUTION.md` — evolution law and size gates
- `scripts/install.sh` — cross-runner symlink installer
- `scripts/validate.sh` — structural validation
