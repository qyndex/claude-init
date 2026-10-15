---
name: 0006-signed-protected-producer-execution-provenance
description: "ADR-0006: Signed protected producer execution provenance"
status: accepted
created: 2026-10-16
metadata:
  type: decision
  status: accepted
---

# ADR-0006: Signed protected producer execution provenance

- **Date**: 2026-10-16
- **Deciders**: @operator (explicit option A approval)
- **Owners**: @operator
- **written_by**: architect
- **source_session**: Codex factory provenance repair
- **last_verified**: 2026-10-16
- **Context**: specs/active/010-protected-proof-producers.md; T-274
- **Tags**: security,provenance
- **subsystem**: factory

## Context

Actual protected producer runs 38813649635 and 38813649657 report their candidate as REST `head_sha`, while GitHub's protected checkout uses `GITHUB_SHA`. Historical `pull_requests` associations change with the PR and cannot authenticate the executed source. Run identity and an artifact digest alone do not prove which protected workflow revision executed.

## Decision

Use the pinned official GitHub attestation action to sign each successful producer's exact evidence root. Verify its bounded bundle cryptographically with GitHub CLI and require certificate-derived protected source, signer workflow/ref, repository, issuer, hosted runner, event and run/attempt. Validate the actual checkout/context/runtime before effects and retain exact candidate/spec/policy/base/AC bindings. Never use mutable associations or an unsigned protected-producer fallback.

On 2026-10-16 the operator approved option A: GitHub-native attestations for the public pilot and solely `id-token: write` / `attestations: write` for the two proof producers. Private/internal adopters require GitHub Enterprise Cloud capability. This does not authorize merge mode or production activation.

## Alternatives considered

- Run/artifact metadata plus self-reported source: insufficient immutable execution-revision proof; rejected.
- GitHub-native attestation: selected; platform certificate identity and existing bounded artifact channel, with an explicit private-repository capability prerequisite.
- Pause and design a private-compatible backend without Enterprise Cloud: not selected now; requires separate design/security review and cannot silently weaken provenance.

## Consequences

Public pilot signing adds narrowly scoped OIDC and attestation permissions. Unsupported private/internal adopters remain blocked for autonomous merge activation while retaining other harness development workflows. Source pins must be refreshed from the reviewed merged revision; live signed producer and shadow proofs remain separate from local tests. Transparency and platform availability are inherited from GitHub's attestation backend.

## Re-verification triggers

Revisit on changes to GitHub target-workflow/OIDC semantics, attestation certificates, GitHub CLI verification flags, action major versions, private-repository availability, or any provenance-related incident.

## References

- Spec: specs/active/010-protected-proof-producers.md
- Plan: plans/active/010-protected-proof-producers.md
- Decision package: docs/activation/2026-10-16/producer-provenance-decision.md
- [GitHub CLI verification policy](https://cli.github.com/manual/gh_attestation_verify)
- [Pinned official signing action](https://github.com/actions/attest/tree/1e69f48acb82d1966a394da916b4c1698aa569d6)
