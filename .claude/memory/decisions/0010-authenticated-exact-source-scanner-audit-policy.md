---
name: 0010-authenticated-exact-source-scanner-audit-policy
description: "ADR-0010: Authenticated exact-source scanner audit policy"
status: accepted
created: 2026-10-16
metadata:
  type: decision
  status: accepted
---

# ADR-0010: Authenticated exact-source scanner audit policy

- **Date**: 2026-10-16
- **Deciders**: @operator (explicit design A approval)
- **Owners**: @operator
- **written_by**: architect
- **source_session**: Codex focused harness maintenance /root/harness_guard_fix
- **last_verified**: 2026-10-16
- **Context**: Spec006 AC11; T329; exact-source audit policy documentation
- **Tags**: architecture security verification
- **subsystem**: factory

## Context

The corrected SARIF gate resolves inherited rule severity and truthfully blocks
an actual retained scan containing two argv-runner audit findings. Local source
and contract triage identifies intentional list-argv launchers in
`factory-worker-guard.py` and `foreground-watchdog.py`; this does not establish a
clean scan or prove isolation. A candidate-controlled suppression or registry
cannot authorize its own exception. The operator approved design A: implement
authenticated exact-source exceptions while leaving their activation separate.

## Decision

Keep the ordinary scanner gate strict and the audit mechanism default OFF.
Audit acceptance requires all explicit policy inputs and an expected SHA256 of
the exact registry bytes obtained from outside candidate control. Validate strict
records binding rule ID, canonical relative path, positive line and whole-source
SHA256, with rationale and approval reference. Reject malformed, ambiguous,
duplicate or changed identities and any additional unapproved effective error.
Numeric security severity at least seven remains unwaivable. SARIF suppression
metadata does not supply approval. Preserve raw scan bytes and report accepted
audit findings distinctly from a clean security scan.

Use the existing narrow supported inline source-location profile. Do not infer
artifact-index or external rule/configuration resolution, supplied source-base
mappings, invocation working-directory overrides or unsupported path semantics.
Source/root symlinks and traversal do not establish identity. Unsupported policy
inputs fail closed; default scanner semantics remain independently enforced.

An opt-in audit producer must run from a frozen main checkout in the fixed,
separately protected main-only `factory-security` environment. Its expected
registry digest is environment-scoped, with no same-named repository/organization
fallback. Candidate execution never receives this protected digest. GitHub's
`vars` context alone cannot prove the variable's origin; independent environment
and credential-authority observations are part of the activation package.

This ADR accepts the architecture, not a live registry or deployment. The initial
two proposed records remain inactive. Concrete activation separately requires
review of exact workflow/gate/helper/registry revisions and source hashes,
main-only environment protections, digest scope, writer-authority boundaries,
retained actual scanner output and negative controls, followed by explicit
operator cutover approval. Carry those observations into T289 readiness. No
environment, variable, secret or opt-in is provisioned by this decision.

## Alternatives considered

- Continue strict blocking with no exception mechanism: remains the default and
  requires no new environment; intentional audited launchers still block.
- Candidate-owned inline suppressions or broad rule/path exclusions: rejected
  because candidate edits could hide unrelated or changed findings.
- Authenticated exact-source exceptions: selected design A. It permits bounded,
  separately approved audit judgments while retaining raw findings and strict
  failure behavior outside the exact reviewed records.

## Consequences and limitations

Every registry/source/rule/path/location change requires renewed concrete review
and a protected digest update. A local simulated digest proves mechanism
behavior, not protected origin, operator activation or hosted execution. Retain
the two actual audit findings and their limitations when reporting acceptance.
Other scanner warnings are not certified safe. This decision grants no merge,
release, credential or production authority.

The legacy worker and watchdog remain intentional argv execution boundaries;
source/argv/guardian contract tests are not a general sandbox proof. Actual Linux
Docker isolation and native same-user filesystem isolation were not established.
Future scanner/profile changes require review rather than silent schema widening.

## Re-verification triggers

Revisit this decision when registry/source identities, SARIF resolution support,
producer workflow or environment protection changes; when credential writers gain
new authority; after an incident involving these boundaries; or after twelve
months. Recheck exact observations before activation or reuse after a change.

## References

- Spec: [Spec006 AC11](../../../specs/active/006-trustworthy-candidate-verification.md)
- Plan: [Plan006 T329](../../../plans/active/006-trustworthy-candidate-verification.md)
- Policy contract: [Exact-source scanner audit policy](../../../docs/security/exact-source-audit-policy.md)
- Evidence: [T329 report](../../../verify/2026-10-16-t329/T-329/REPORT.md)
- Related decisions: ADR-0006 (protected producer provenance), ADR-0008 (protected policy observations)
