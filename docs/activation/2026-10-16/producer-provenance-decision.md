# Protected producer provenance repair

Status: operator approved option A on 2026-10-16: GitHub-native attestation for the public pilot, explicit Enterprise Cloud prerequisite for private/internal adopters, and solely the two producer workflows’ proof-signing permissions. This approval does not enable factory merge mode or production.

## Observed failure

PR #106 merged as `d036af6740cb8e4b9cf56a640ff796f617b191ee`.
Pilot PR #101 then ran at candidate `78c690b78c856369d8e2e2f0efa35e9ec71132bf`.
The [verification run](https://github.com/qyndex/claude-init/actions/runs/38813649635)
and [review run](https://github.com/qyndex/claude-init/actions/runs/38813649657)
both stopped before candidate acceptance or model execution. The implementation
required REST `run.head_sha` to equal the protected base. Those runs report the
candidate SHA in that field; their protected checkout used `d036af67…`.

Historical run `38139128097` retained its original immutable head SHA while its
`pull_requests` association reported the pilot's newer base and head. Therefore
that association cannot establish the source revision executed by an old run.

## Approved repair (option A)

Keep the existing Spec010 AC-1/AC-4 contract. Authenticate the immutable candidate
run and separately authenticate the protected execution source:

1. Validate the producer's GitHub execution context, exact run and attempt,
   protected branch, checkout revision, and pinned local runtime bytes before
   acceptance or model invocation. Require the protected source to equal the
   current PR base.
2. Sign the exact `evidence.json` digest with a commit-pinned official
   `actions/attest` step after proof succeeds. The root document binds observation
   digests. Preserve its signed bundle with the existing bounded proof artifact.
3. Have the coordinator cryptographically verify the bundle using GitHub CLI.
   Enforce repository, exact workflow/ref and source revision, issuer, hosted
   runner and run/attempt using authenticated certificate claims. User-controlled
   predicate fields alone cannot prove execution identity.
4. Retain the current runtime pins, artifact digests, spec/policy/AC bindings,
   candidate freshness checks and rejection of authority-path changes. Reject
   absent, stale, malformed, tampered or unsigned provenance.
5. Require signing, bundle preservation and artifact upload to succeed before
   publishing a successful producer check.

The operator approved the two producer jobs gaining `id-token: write` and `attestations: write` to
sign proof bundles. The factory App gains no permissions. Merge mode, production,
live rulesets and other integrations are outside this repair's permission change.

GitHub-native attestations support this public pilot on current GitHub plans.
Private/internal repositories require Enterprise Cloud. Adopter documentation
must state this capability prerequisite for autonomous merge activation; it must
not claim all private repositories can activate the factory or accept unsigned
proof as a fallback. This does not prevent copying or using the harness's other
development workflows.

## Alternative not selected (option B)

Keep the pilot paused and first design a provenance mechanism that supports
private repositories without Enterprise Cloud. That requires a separate design
and security review before implementation or activation. No alternative service,
credential, cost or trust boundary is selected by this document.

## Verification and activation sequence

- T-274 records failing regressions before implementation. Cover immutable
  candidate identity, same-head stale-base runs, foreign workflow/repository,
  wrong event/run/attempt, local checkout/runtime mismatch, missing or altered
  signatures, forged evidence bases and archive limits.
- Distinguish injected cryptographic-verifier fixtures from genuine signed proof.
  A local fixture pass cannot close T-180 or T-222.
- Complete source review and required CI. Record the source commit before
  refreshing runtime hashes in protected policy.
- The operator approved the selected approach and the scoped signing permission
  change. After source review and required CI, merge through the existing operator route, refresh the pilot against
  the resulting protected base, and retry genuine producers.
- Apply only the reviewed additive shadow ruleset after genuine proof succeeds.
  Shadow eligibility remains separate from approval to enable merging.

At preparation time, `FACTORY_PRODUCERS_ENABLED=false`,
`FACTORY_AUTHORITY_ENABLED` is unset and `merge_enabled=false`. PR #101 is a draft.
Reporting and approved encrypted feedback remain enabled.

## Primary references

- [GitHub target-workflow execution](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target)
- [GitHub CLI verification and certificate policy](https://cli.github.com/manual/gh_attestation_verify)
- [Official attestation action and repository-plan availability](https://github.com/actions/attest-build-provenance#readme)
- [Current official attestation action](https://github.com/actions/attest)
