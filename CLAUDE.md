# idd-skills repository conventions

## Sources of truth

Author `/idd` in `skills/idd/SKILL.md` and `/idd-evolve` in `skills/idd-evolve/SKILL.md`. `CONSTITUTION.md` governs methodology changes. Do not create a `commands/` mirror; Claude Code, Codex, and Pi consume the same Agent Skills sources through symlinks created by `scripts/install.sh`.

## Scope

IDD is the lightweight, existing-repository issue implementation workflow. `/idd` must not absorb CDD's PRD, golden-file, sibling-repository, trace, mandatory peer-review, acceptance-wave, auto-merge, or deploy machinery. Evolution stays in the separate `/idd-evolve` command and never adds artifacts to project repos. Prefer repository-native tests and git/PR history.

## Editing discipline

- Keep `skills/idd/SKILL.md` at or below 160 lines and `skills/idd-evolve/SKILL.md` at or below 80.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Kept evolve changes commit and push directly to `main`; never auto-merge project PRs or force-push.
