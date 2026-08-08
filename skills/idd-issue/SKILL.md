---
name: idd-issue
description: "Create one implementation-ready GitHub issue in an existing repository from user-provided evidence. Use when the user explicitly asks to file, create, or open an issue; drafting alone never mutates GitHub."
compatibility: "Requires git and GitHub CLI (gh); works with Claude Code, Codex, Pi, and OpenCode."
argument-hint: "[request] [--repo OWNER/REPO]"
---

# /idd-issue — create one implementation-ready issue

Turn a concrete problem or change request into one live GitHub issue. Keep it small enough for one `/idd` run. Do not create branches, edit project files, prescribe speculative implementation, or start delivery.

An explicit request to **file**, **create**, or **open** the issue authorizes one GitHub issue creation. A request to draft, review, or suggest does not.

## Establish the boundary

1. Resolve the target repository from `--repo`, an issue/repository URL, or the current checkout; never guess between plausible repositories. Confirm `gh auth status` and read repository contribution guidance and issue templates.
2. Search open and closed issues for the same outcome. Stop with the existing issue when it is a likely duplicate.
3. Inspect only the source evidence needed to make the issue accurate. Preserve uncertainty; never invent reproduction results, affected paths, labels, owners, or priority.
4. Ask one focused question only when repository, scope, or expected behavior is materially ambiguous. Otherwise proceed from the explicit creation request.

## Draft minimally

Follow the repository template. If none exists, use only the sections that add information:

- a specific outcome-oriented title;
- problem and concrete evidence;
- proposed outcome or scope boundary;
- testable acceptance criteria;
- non-goals or verification when they prevent ambiguity.

Use existing labels only when clearly justified. Exclude credentials, account names, home paths, and unrelated follow-ups. Write multiline bodies through `gh issue create --body-file`, not shell interpolation.

## GATE — create and verify exactly one issue

Before creation, require a coherent single issue, a completed duplicate search, evidence-backed claims, and acceptance criteria sufficient to judge completion. If creation returns an ambiguous result, search before retrying so a timeout cannot create a duplicate.

Create once, then read the issue back with `gh issue view`. Verify its repository, title, body, labels, `OPEN` state, and canonical URL. Report only the created issue number, title, URL, and any deliberately omitted uncertainty.
