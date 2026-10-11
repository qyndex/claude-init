# Factory activation decision package — 2026-10-11

This package is proposal-only. The live factory/policy.json and GitHub switches remain unchanged. Claude review/security stay paused until Tuesday. Preparing or merging this package does not approve spec 048, apply the ruleset, enable producers/authority or permit any merge. The concrete operator decision concerns the exact pilot spec and shadow-only policy bytes below, after genuine runtime readiness is demonstrated.

## Reviewable inputs

- manifest.json: source revision, actual workflow IDs, observed pause/environment/switch state and operational blockers. Secret-name metadata only; no secret bytes were retrieved. Presence does not prove key pairing, token usability or quota.
- policy.shadow.proposed.json: complete trusted runtime hashes, proposed spec 048 hash/ACs/exact documentation path, protected per-AC commands and a registry-resolved immutable Python image. enabled=true permits shadow evaluation only after reviewed application; merge_enabled=false always blocks merge mode. This file is not loaded by any live workflow.
- ruleset.proposed.json: full additive proposal preserving live controls, including all twelve producer-pinned contexts. No live rules were changed.
- preflight.live.json: actual disabled live-policy blockers. preflight.shadow.json: structural readiness of proposed bytes with observed App/secret-presence metadata. Neither is live independent execution proof.
- shadow-cases.json: required positive/negative cases; live_executed=false. Existing coordinator fixtures provide local failure coverage only.

## Ordered activation and proof

1. Now: review package hashes, source/runtime pins, proposed pilot spec, image and exact scope. Keep all enablement switches off. Refresh source/pins/proposal if trusted runtime, target rules or spec bytes change; rerun preparation checks.
2. Tuesday: confirm real subscription availability and observed model identity, without metered fallback. A credential-presence or help response cannot establish quota. Restore paused legacy review/security only at the agreed time. Do not issue model calls before then.
3. Obtain the concrete operator decision for exact spec 048 and shadow configuration. Promote spec-048.proposed.md and plan-048.proposed.md to their declared specs/active and plans/active destinations, check proposed spec/task IDs against active and archived ledgers, reserve T-222 only if still available (otherwise mint fresh IDs and refresh all bindings), and change the spec's frontmatter to approved only after that decision, recompute its digest and policy hash, and commit the reviewed authority configuration on protected main. Proposal hashes are deliberately not claimed as final approval. Re-run preflight, record the resulting actual Git commit and refresh receipt runtime pins; never guess a future/self-referential SHA.
4. Enable protected producers for the controlled pilot, leaving merge_enabled=false. Open factory/spec-048/adopter-quickstart changing only the approved document. Retrieve real separate workflow runs and artifacts; inspect exact head/base/spec/policy/model bindings and complete AC observations. Candidate code runs offline without privileged credentials.
5. Review/apply the additive protection proposal using the operator administration identity, after producer identities and runnable checks are proven. Disable already-armed native auto-merge requests at cutover; no bypass actor is added. Set authority evaluation only for shadow mode. Retain all blocker results and the positive eligible-without-merge result in shadow-cases.json's external evidence record. Deliberately defective negative candidates must never merge. Refresh proofs after any base/head/policy change.
6. Present genuine shadow evidence and the exact merge-mode revision for a separate operator decision. Before the first actual merge, register the real coordinator source revision and runtime hashes in the protected receipt-consumer policy. The package leaves receipts.trusted_revisions empty because no approved live merge source exists yet; its preflight structural PASS is not receipt-ingestion readiness.
7. Deliver one approved candidate through conditional merge. Preserve the actual returned merge SHA and authenticated coordinator receipt; reconcile uncertain effects before retry. Confirm next 08:00 Sydney digest, then authenticated real operator feedback. Approve a separate feedback amendment and deliver it through the same spec chain. Product acceptance is a distinct decision.
8. Collect twenty genuine consecutive eligible deliveries with complete receipts and recovery/reporting proof before expanding autonomy. Manual harness preparation PRs and fixtures do not count. Per-adopter online workers/production remain independently gated; oversized attachments and Healthchecks remain disabled.

The maintained package test validates preparation facts against the recorded source revision, so later legitimate activation, pilot delivery and runtime upgrades do not invalidate historical evidence. Current readiness must be checked separately immediately before applying refreshed configuration. Spec 048 and T-222 are proposed identities until promotion; no ledger reservation is claimed.

## Commands for review (no mutation)

```sh
python3 .claude/scripts/factory-preflight.py --policy docs/activation/2026-10-11/policy.shadow.proposed.json
python3 .claude/scripts/factory-ruleset-plan.py --policy docs/activation/2026-10-11/policy.shadow.proposed.json --ruleset-id 19653920 --app-id 5251754 --output /tmp/rechecked-factory-ruleset.json
bash .claude/scripts/test/factory-activation-package.sh
```

Preflight requires the actual protected App ID and secret-presence signal; do not paste key/token bytes into shell history or chat. This package's saved result used metadata only. The selected pilot ruleset ID belongs solely to qyndex/claude-init; adopters select their own applicable ID.

## Rollback and pause

Record the live before-image and actual approved configuration commit before applying any authority revision. To pause future evaluation/merges, disable the authority/producers switches through the operator route, preserve in-flight uncertain effects and receipts, and keep production disabled. Revert configuration via a reviewed PR naming the actual activation commit; do not revert an unrelated local HEAD. Product rollback uses the recorded delivery merge SHA and approved rollback route. Restoring a ruleset must use its reviewed before-image and preserve stricter intervening changes. No rollback command is issued by this package.
