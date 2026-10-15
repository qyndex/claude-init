# Signed-producer shadow pin refresh

Protected runtime source: actual merged repair `bc678f611e7c2e05b1eb427e805654644c84dd67` (PR #107). Its final required checks and independent review/security passed before merge. This package derives each role's complete seven-file runtime pin set from `git show <source>:<path>`, including the signed-provenance helper. `factory/policy.json` changes only the two producer `trusted_files` maps. All other policy fields remain byte-equivalent after parsing: approved spec048 and nine allowed paths, per-AC argv, image digest, required check producers, `merge_enabled=false`, and empty receipt trusted revisions.

The preceding package at `docs/activation/2026-10-16` remains historical. Its missing signed-provenance helper is rejected by the current metadata preflight. The new complete pin map passes the same preflight with explicit App ID and key-presence declarations. Those declarations prove configuration structure only: no key was read, App token minted, hosted review authenticated or signed evidence produced.

Fresh GET-only reads preserve current live protection. `ruleset.proposed.json` is the actual existing planner output: twelve exact producer pins, strict required checks, no bypass actors, and preservation of all other rules/conditions. It has not been applied. Re-read and compare the before-image immediately before any reviewed cutover; preserve stricter intervening controls.

The operator approved GitHub-native attestations and solely proof-signing permissions for the two producer workflows, as recorded in ADR0006 and the preceding decision package. Public repositories support this backend; private/internal adopters require GitHub Enterprise Cloud capability. Enterprise Cloud attestation capability is necessary but not sufficient: private adopters must separately prove secure private-candidate retrieval and all native/shadow gates; this public pilot does not certify private operation or add a private-fetch adapter. Unsupported adopters fail closed. This package grants no additional permissions, authority, production or merge-mode approval.

Next sequence: review this pin-only source change and required CI; merge it through the existing operator route; refresh the exact nine-path pilot against the resulting protected base; obtain genuine separate signed verifier/reviewer artifacts; complete reviewed additive protection/shadow evaluation and negative cases; then present the separate merge-mode decision. T-180 stays blocked and T-222 stays pending. Receipt trusted revisions stay empty until registering the actual authorized merge-source revision in its later approved step.

No workflow switch, live ruleset, pilot branch, merge mode, secret or production setting changed while preparing this package. Reporting and previously approved encrypted feedback are unaffected. Rollback pauses producers/authority before an approved pin-policy rollback PR; any rules rollback must use the recorded before-image while preserving stronger intervening controls.

Reproduce the metadata proposal (GET requests only):

```sh
python3 .claude/scripts/factory-ruleset-plan.py \
  --policy factory/policy.json --ruleset-id 19653920 --app-id 5251754 \
  --output /tmp/signed-shadow-ruleset.proposed.json
```

Local metadata/preflight proof and injected coordinator contracts are implementation evidence, not live signed factory proof. See `source.json` and `manifest.json` for actual source/file digests and the complete preflight declaration boundary.

References: accepted `.claude/memory/decisions/0006-signed-protected-producer-execution-provenance.md`; approved `plans/active/009-protected-factory-activation.md`; [GitHub attestation repository-plan requirements](https://docs.github.com/en/enterprise-cloud%40latest/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations).
