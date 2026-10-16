---
name: 0008-protected-policy-observations
description: "ADR-0008: Exact protected operator policy observations"
status: accepted
created: 2026-10-16
metadata:
  type: decision
  status: accepted
---

# ADR-0008: Exact protected operator policy observations

- **Date**: 2026-10-16
- **Deciders**: @operator (explicit option A approval)
- **Owners**: @operator
- **written_by**: architect
- **source_session**: Codex factory policy visibility repair
- **last_verified**: 2026-10-16
- **Context**: specs/active/010-protected-proof-producers.md; T-292
- **Tags**: security,protection
- **subsystem**: factory

## Context

Protected shadow run38826696104 failed closed after App minting because the
Administration-read API omits bypass_actors. Operator GET actually exposed empty
actors. GitHub documents this visibility restriction at
https://docs.github.com/en/rest/repos/rules. Increasing Administration permission
would let the enforcing credential modify its own protection.

## Decision

The operator approved option A on 2026-10-16: preserve Administration read and
require an exact administrative observation for omitted actors only. Bind a strict
bounded protected input to repository/ruleset identity, stable complete metadata
hash, server updated_at and observed_at after60seconds settling and before now.
Visible nonempty/malformed actors always reject; visible empty remains direct.
Any metadata change invalidates approval. All live protection/pin checks remain.

Store nonsecret observation configuration outside canonical policy and Git in the
main-only authority environment. GET-only generation requires actual explicit
empty actors; candidate/body claims never qualify. A separate bounded audit
artifact may retain the observation/hash without changing the single-member
receipt ZIP. Administrative approval is not portable native cryptographic proof.

## Consequences and boundaries

No App permission, credential, flag or protection change is included. Source review
and separately approved maintenance remain necessary. The new helper enters every
transitive protected producer pin and proof material set. Separate Spec014 emitter
closure/material integration remains pending; no active content profile is implied.
Administration-write and an omitted-metadata automatic fallback are rejected.
