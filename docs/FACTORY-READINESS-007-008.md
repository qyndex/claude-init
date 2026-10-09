# Factory readiness: required verification and candidate evidence

This implementation continues the operator-approved factory plan, following baseline repair 006. It does not enable unattended merges or releases.

## Required verification (007)

`verify.sh` rejects requested SKIP flags regardless of the old local marker or claimed CI environment. No externally authenticated waiver service is installed. Applicable Playwright browser provisioning failure now blocks. Stack detector failures, invalid JSON, duplicates and unknown runtimes block; every detected language needs its own test invocation. Numeric coverage gates now reject null, strings and percentages outside 0–100, and compare decimal percentages without truncation. Coverage adapters for Java/Ruby/.NET/PHP and full workspace coverage completeness remain required before F-00 closes.

`rerun-acceptance.py` compares candidate task state against a resolvable explicit base or known main/master merge-base, including detached checkouts. It validates duplicate IDs and acceptance declarations, reruns every newly completed task with Bash pipefail and a bounded subprocess process group, and kills the group on timeout. Missing base history or commands blocks. GitHub evidence reexecution passes the PR base SHA and no longer requests unverified equivalent-CI skips.

Acceptance commands are candidate code and require an isolated runner without privileged tokens. This parser does not authenticate task completion or approved task content. The approved task/spec authority store remains F-01 work.

## Candidate evidence core (008)

`validate-candidate-evidence.py --context <protected-context.json> --evidence <candidate-evidence.json>` checks versioned strict JSON, exact repository/PR/head/base/spec/policy bindings, complete and unique approved AC IDs, passing observations with artifact digests, exact successful required check receipts with configured producer App IDs, separate authorized verifier/reviewer actors, no unresolved findings and a trusted run window. Duplicate JSON keys, unexpected fields and null/missing arrays fail.

The regression test contains a complete valid example of both documents and 26 rejection cases. Production context must come from protected approved storage and authenticated GitHub API data. The coordinator must retrieve check runs and independent verdict artifacts itself, verify artifact bytes against digests, resolve expected actor identities, and supply a bounded run window. Candidate-provided actor names/App IDs are not attestations. This core is deliberately not wired to auto-merge or treated as a replacement for CI/security review.

## Remaining activation dependencies

1. Protected spec/task revision and applicability authority; complete coverage adapters and trusted waivers.
2. GitHub App provisioning and protected coordinator receipt retrieval, including verifier/reviewer artifact authentication.
3. Unified exact-head merge eligibility, candidate-bound batch receipts and rollback PRs across all merge routes.
4. Durable task claims/recovery and immutable delivery receipts.
5. Slack delivery to qyndex / qyndex-alerts at 08:00 Australia/Sydney, with idempotent delivery and feedback amendments.
6. Production environment gates, missing-metric failure, canary health and automated rollback before autonomous releases.

Validation outputs are local implementation evidence, not independent attestation or a successful GitHub run. Original audit and spec-006 reports remain historical records.

## Verification record

- Maintained suite baseline after 007/008: **61/61 macOS and 61/61 Linux passed**, in disposable copies retaining Git history. The earlier copy without Git history produced one provenance failure; restoring the required history resolved it without changing product code.
- After the subsequent numeric-coverage repair, focused coverage, detached acceptance, per-stack/waiver, candidate-root and candidate-evidence regressions are rerun on both platforms. See final focused logs for that source revision.
- The evidence contract fixture passes **27 checks**; acceptance **8**, required verification **7**, coverage percentages **6**.
- Structural validation: **79 passed, one existing historical no-op acceptance warning, zero failures**. Required TDD ledger passes with historical exemptions still reported. Workflow expression lint and warning-level ShellCheck pass for changed shell code.
- Existing initiative state hashes match the original full-audit inventory. No GitHub App, CI candidate run, PR, automatic merge, production release or Slack schedule has been activated.

Red logs contain the regression baseline output; their ledger headers use capture-file modification times. They are local test evidence, not signed CI receipts. Spec 008's red baseline is the deliberately permissive validator scaffold used before implementing the rejection rules.
