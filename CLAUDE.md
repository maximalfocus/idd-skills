# idd-skills repository conventions

## Sources of truth

Author `/idd-plan`, `/idd-issue`, `/idd`, `/idd-land`, `/idd-auto`, and `/idd-evolve` in their matching `skills/*/SKILL.md` sources. `CONSTITUTION.md` governs methodology changes. Do not create a `commands/` mirror; Claude Code, Codex, Pi, and OpenCode consume the same Agent Skills sources through symlinks created by `scripts/install.sh` (OpenCode discovers the shared `~/.agents/skills/` links). Keep skill inputs portable: runners that do not inject `$ARGUMENTS` must be able to use the user's request.

## Scope

IDD is the lightweight issue workflow. `/idd-plan` may bootstrap only a private PRD plus progress tracker, after product-requirement approval or reconstructed from an implemented repository's source and delivery history; otherwise it consumes an exact convention-linked pair, recommends one next issue, or reconciles verified tracker state. It never creates plan files or issues. `/idd-issue` creates one evidence-backed issue; `/idd` must not absorb CDD's golden-file, trace, mandatory peer-review, acceptance-wave, or deploy machinery. `/idd-land` is the gated merge/closure phase and reconciles an exact associated PRD after landing. `/idd-auto` may sequence those current phases only after explicit invocation, one issue at a time, and must stop on any red or ambiguous gate. Evolution stays in `/idd-evolve`. Prefer repository-native tests and git/PR history.

## Editing discipline

- Keep `skills/idd-plan/SKILL.md` ≤90 lines, `skills/idd-issue/SKILL.md` ≤70 lines, `skills/idd/SKILL.md` ≤160, `skills/idd-land/SKILL.md` ≤120, `skills/idd-auto/SKILL.md` ≤120, and `skills/idd-evolve/SKILL.md` ≤80.
- Script deterministic installation/validation work; keep implementation judgment in prose.
- Stage only task-owned paths explicitly; never use `git add -A`.
- Run `bash scripts/validate.sh` before committing.
- Kept evolve changes commit and push directly to `main`; only explicit `/idd-land` or `/idd-auto` authority may merge a project PR, and neither may force-push.
