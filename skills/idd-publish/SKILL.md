---
name: idd-publish
description: "Safely complete the publication slice for an exact private IDD project pair, making only the implementation repository public after its preparation issue lands."
compatibility: "Requires git, GitHub CLI (gh), and the exact {project} ↔ {project}-prd pair."
disable-model-invocation: true
argument-hint: "[project-name|repository-path]"
---

# /idd-publish — publish one exact IDD project

An explicit `/idd-publish` invocation authorizes the final visibility mutation for the exact pair: update both repositories through one publication-preparation issue, branch, PR, squash merge, closure, and tracker reconciliation, then make only `{project}` public. `{project}-prd` remains private. This is repository publication, not deployment or hosting.

## Orient and prepare

1. Resolve this skill's physical source repository, not the harness symlink that installed it, and run its `scripts/resolve-prd-pair.sh`. Require matching origins, authenticated GitHub access, clean default branches, and both repositories currently private. Read `PRD.md`, `PROGRESS.md`, live issues/PRs, and repository instructions.
2. Resume one uniquely active publication issue/PR; otherwise execute `/idd-plan` for the next publication requirement, then `/idd-issue`, `/idd`, and `/idd-land`. Preserve every constituent duplicate, acceptance, verification, review, merge, cleanup, and reconciliation gate. Never parallelize or invent requirements.
3. Before publication, require a license, defaulting to MIT when the project does not specify one, plus public-safe documentation, a green repository-native gate and end-to-end check, and no unresolved product or legal decision. The preparation issue must be landed while the implementation repository is still private. Run the publication gate's denylist and secret scan over the preparation change before pushing it, including any guard or test that names a forbidden term in order to forbid it; once merged, a match survives in the provider's retained pull-request refs, which no history rewrite can reach.

## Publication gate

Scan Git content with that same source repository's `scripts/scan-exposure.sh <impl-path> <term>…`, which covers every commit message and every blob across all refs including retained PR refs, applies the mandatory denylist, and fails closed. Run it; never hand-reimplement its sequence, and never substitute the project's own exposure check, which may exclude the paths carrying the term. Supply as terms the companion PRD owner/name, URL, and local path, every private companion repository and document, and user/project-supplied real governments, public authorities, agencies, organizations, products, aliases, and abbreviations. Name a private document by its bare stem, never anchored to a file extension: a term written `NOTES.md` must still match `NOTES §2`, which is how such a name usually appears in prose. Refer to private companion material only generically in implementation commit messages, issues, PRs, and comments.

Then audit by hand what the script cannot reach: branches/tags/releases, repository metadata, issues, comments, reviews, edit revisions, Actions runs/logs/artifacts, and package or documentation links. Any match blocks visibility: remove or fictionalize it in source and provider content and purge it from Git history/retained refs rather than deleting only the current file; if that requires ungranted history-rewrite authority or the provider cannot purge a retained surface, stop with that interactive blocker. A commit-message match is always that blocker — retained pull-request refs keep the commit reachable, so no history rewrite removes it, and the only remaining choices are publishing from a fresh repository or the user knowingly accepting it. Resolve or remove unsafe public-facing history before proceeding; never expose credentials, personal data, private PRD links, or private operational rationale. Do not deploy, host, or publish packages.

Change visibility only after all gates pass, using the provider's explicit visibility command for `{project}`. Do not change `{project}-prd`. Verify anonymous HTML/raw/clone access for the implementation repository and anonymous denial for the PRD; verify public issue/PR pages contain no private links. Enable repository security reporting only when required by the accepted publication requirements.

## GATE — fail closed or finish

Stop with one precise, resumable blocker if pair identity, privacy state, license, exposure audit, secret scan, checks, review, or readback is ambiguous or red. On success, reconcile only the exact PRD `PROGRESS.md` row with issue/PR/squash and public/private readback evidence; advance its lifecycle status only when the tracker's own definitions and every requirement represented by that row are satisfied. Commit and push it, then verify both trees and default branches are clean and synchronized. Return the issue/PR URLs, final commits, visibility evidence, and `complete`.
