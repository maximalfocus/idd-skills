# idd-skills repository conventions

## Source of truth

Author `/idd` only in `skills/idd/SKILL.md`. Do not create a `commands/` mirror; Claude Code, Codex, and Pi consume the same Agent Skills source through symlinks created by `scripts/install.sh`.

## Scope

IDD is the lightweight, existing-repository issue implementation workflow. It must not absorb CDD's PRD, golden-file, sibling-repository, trace, mandatory peer-review, acceptance-wave, auto-merge, deploy, or methodology-evolution machinery. Prefer repository-native tests and git/PR history over new artifacts.

## Editing discipline

- Keep `skills/idd/SKILL.md` at or below 160 lines.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Do not auto-merge or force-push.
