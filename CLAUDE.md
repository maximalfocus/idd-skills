# idd-skills repository conventions

## Sources of truth

Author `/idd-plan`, `/idd-issue`, `/idd`, `/idd-land`, and `/idd-evolve` in their matching `skills/*/SKILL.md` sources. `CONSTITUTION.md` governs methodology changes. Do not create a `commands/` mirror; Claude Code, Codex, Pi, and OpenCode consume the same Agent Skills sources through symlinks created by `scripts/install.sh` (OpenCode discovers the shared `~/.agents/skills/` links). Keep skill inputs portable: runners that do not inject `$ARGUMENTS` must be able to use the user's request.

## Scope

IDD is the lightweight, existing-repository issue workflow. `/idd-plan` only consumes an existing convention-linked PRD, recommends one next issue, and reconciles its existing tracker from live state; it never creates planning artifacts or issues. `/idd-issue` only creates one evidence-backed issue; `/idd` must not absorb CDD's PRD, golden-file, trace, mandatory peer-review, acceptance-wave, auto-merge, or deploy machinery. `/idd-land` is a separate explicit merge/closure command, must fail closed on red gates or undisclosed residuals, and automatically reconciles an exact associated PRD after landing. Evolution stays in `/idd-evolve`. Prefer repository-native tests and git/PR history.

## Editing discipline

- Keep `skills/idd-plan/SKILL.md` ≤90 lines, `skills/idd-issue/SKILL.md` ≤70 lines, `skills/idd/SKILL.md` ≤160, `skills/idd-land/SKILL.md` ≤120, and `skills/idd-evolve/SKILL.md` ≤80.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Kept evolve changes commit and push directly to `main`; never auto-merge project PRs or force-push.
