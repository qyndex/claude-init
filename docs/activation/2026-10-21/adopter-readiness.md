# Adopter readiness — 2026-10-21

The original closed task baseline is historical evidence. The additional native-build, receipt-profile, reporting and adopter work is not an end-to-end readiness certificate. This update describes a source candidate, not an activation approval.

## Verified progress

- Queue retry PR134 merged as `c7b13f0f15c535a0df9b4ae6d76d19db4e6a3838`; independent readbacks verified all twelve strict requirements, no bypass and restoration of only the existing narrow authority.
- Native/profile PR137 and brownfield helper PR3 were published with exact head/body readbacks. Their superseded PRs were closed unmerged. New source after those heads requires fresh checks; their results do not transfer.
- Brownfield PR3 passed seven ordinary application/process checks. Its full local Spec001 collector remains 0/8 with smoke passing; workflow success is not protected acceptance.
- The additive receipt profile preserves both historical profiles. Local source, revocation and campaign controls pass. Full Spec010/014 collectors remain 0/5 and 0/8 respectively, with smoke passing. Original reporting-source replay remains pending.
- The one approved queue diagnostic retained only `queue-reconcile / metadata-clock-invalid`, with private-cache cleanup verified. A local clock regression reproduces a defect consistent with this category; it does not establish the unique live cause or prove recovery.

PR137's structured harness check found missing executable bits on two tests and an invalid duplicate plan document. A separate local native/profile candidate corrects that packaging and retains the failure. This clock-only candidate does not include those native/profile changes. The clock repair and the separate packaging corrections each require final-head checks and review; local results cannot stand in for them.

## Remaining acceptance

1. Complete final-head native checks and independent reviews; obtain a reviewed protection/runtime/receipt-profile cutover before restoring authority on changed trusted source.
2. Merge and trust the font adapter, then qualify each adopter's exact spec, verifier image, protected credentials, signed shadow evidence and negative controls. Installers keep capabilities disabled until those repository-specific gates pass.
3. Confirm actual pilot digest delivery and cutoff, then genuine allowlisted feedback and its approved delivery cycle. A successful scheduled workflow alone is insufficient.
4. Accumulate the required useful delivery sample naturally. Fixtures, maintenance merges and local tests do not count as product deliveries.

Greenfield `qyndex/qynise-platform` and brownfield `qyndex/nextjs-landing-page` retain separate state and approvals while sharing the approved Slack destination. Greenfield local qualification is not hosted acceptance. Brownfield font installation remains a later bounded change, dependent on the trusted adapter and its exact registration.

Application provider execution and production identity/cloud/deployment remain explicitly deferred. Use the [adopter quickstart](../../FACTORY-ADOPTER-QUICKSTART.md) and [per-repository setup](../../FACTORY-ADOPTER-SETUP.md); installation does not activate authority or supply another repository's credentials. The older [status snapshot](../../FACTORY-STATUS.md) and [master plan](../../../plans/AI-SOFTWARE-FACTORY.md) retain dated history, not current switch settings.
