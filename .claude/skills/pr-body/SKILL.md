---
name: pr-body
description: Write or refresh a pull request title and body for this harness, including approved spec references, complete acceptance evidence, actual validation results, and remaining risks. Use before opening a PR or updating its scope or proof.
---

# PR body

Read the final diff, approved specs and plans, and actual check output before writing. Use the repository's [PR template](../../../.github/PULL_REQUEST_TEMPLATE.md) as the outline. Lead with the concrete problem and resulting behavior; rewrite the title and summary if scope changed.

## Evidence contract

- Identify every spec touched or implemented by the final diff, with its plan and task IDs. Do not choose only the newest evidence directory when multiple specs apply.
- Run `bash .claude/scripts/collect-evidence.sh <spec-id>` for each applicable spec. Include each resulting `pr-body.md` evidence block in full, alongside the summary. A failed collector means verification is incomplete; report it and keep the candidate a draft rather than inventing a PASS.
- Commit the lightweight proof files required by the shipping workflow. Run `python3 .claude/scripts/check-local-evidence.py --changed-files <diff-file>` against the final changed-file list before publishing. The list should come from `git diff --name-only <base>...HEAD`, using the PR's actual base.
- State which commands actually ran, their results, relevant artifact paths or CI links, and what remains untested. Distinguish local implementation proof from authenticated independent verifier/reviewer receipts. Pending, skipped, and historical checks are not current-head successes.
- Use the existing no-AC policy only when the entire diff qualifies. Describe its scope and actual validation; never fabricate acceptance counts to fill the template.
- Describe material risks and a rollback approach. For merged factory candidates, rollback targets the recorded merge SHA through an approved rollback PR.

## Publish and maintain

Save the complete body to a file, preserving actual newlines and literal command text. Publish using `gh pr create --body-file <file>` or `gh pr edit <number> --body-file <file>`. `--fill` alone and a one-line verification summary do not satisfy the evidence contract. This applies to swarm and scripted PR creation too; supply the same complete body to those paths.

Read back `gh pr view <number> --json title,body,headRefOid` and confirm that the published body includes every applicable bundle and describes the current candidate. Refresh claims after source or scope changes; link final-head CI once available. In Codex, attach any newly created PR with the app's attachment tool.

Writing a body does not authorize merging or deploying. Request factory evaluation through `autonomous-ship.sh`; actual merge status comes from GitHub and its receipt. The required evidence gate remains the enforcement layer if skill invocation is missed.
