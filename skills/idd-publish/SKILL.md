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

1. Resolve the exact pair with `scripts/resolve-prd-pair.sh`. Require matching origins, authenticated GitHub access, clean default branches, and both repositories currently private. Read `PRD.md`, `PROGRESS.md`, live issues/PRs, and repository instructions.
2. Resume one uniquely active publication issue/PR; otherwise execute `/idd-plan` for the next publication requirement, then `/idd-issue`, `/idd`, and `/idd-land`. Preserve every constituent duplicate, acceptance, verification, review, merge, cleanup, and reconciliation gate. Never parallelize or invent requirements.
3. Before publication, require a license, defaulting to MIT when the project does not specify one, plus public-safe documentation, a green repository-native gate and end-to-end check, and no unresolved product or legal decision. The preparation issue must be landed while the implementation repository is still private.

## Publication gate

Audit the complete public exposure surface: current files and every Git object/ref (including deleted branches and PR refs), branches/tags/releases, repository metadata, issues, comments, reviews, edit revisions, Actions runs/logs/artifacts, and package or documentation links. Secret-scan the repository. Apply a case-, punctuation-, spacing-, and spelling-tolerant denylist whose minimum terms are [removed], [removed], [removed], [removed], [removed], and [removed], plus user/project-supplied real governments, public authorities, agencies, organizations, products, aliases, and abbreviations. Treat the companion PRD owner/name, URL, and local path as mandatory denylist terms, and refer to it only generically in implementation issues, PRs, and comments. Any match blocks visibility: remove or fictionalize it in source and provider content and purge it from Git history/retained refs rather than deleting only the current file; if that requires ungranted history-rewrite authority or the provider cannot purge a retained surface, stop with that interactive blocker. Resolve or remove unsafe public-facing history before proceeding; never expose credentials, personal data, private PRD links, or private operational rationale. Do not deploy, host, or publish packages.

Change visibility only after all gates pass, using the provider's explicit visibility command for `{project}`. Do not change `{project}-prd`. Verify anonymous HTML/raw/clone access for the implementation repository and anonymous denial for the PRD; verify public issue/PR pages contain no private links. Enable repository security reporting only when required by the accepted publication requirements.

## GATE — fail closed or finish

Stop with one precise, resumable blocker if pair identity, privacy state, license, exposure audit, secret scan, checks, review, or readback is ambiguous or red. On success, reconcile only the exact PRD `PROGRESS.md` row with issue/PR/squash and public/private readback evidence; advance its lifecycle status only when the tracker's own definitions and every requirement represented by that row are satisfied. Commit and push it, then verify both trees and default branches are clean and synchronized. Return the issue/PR URLs, final commits, visibility evidence, and `complete`.
