---
name: 0000-decision-template
description: ADR template — copy to a new file and fill in.
metadata:
  type: decision
  status: template
---

# ADR-0000: <Decision Title>

- **Status**: proposed | accepted | superseded by ADR-XXXX | deprecated
- **Date**: YYYY-MM-DD
- **Deciders**: <names or @handles>
- **Owners**: [@<human-owner>]    # who answers if this needs revisiting
- **written_by**: human | architect | dream | reviewer | debugger | security   # Round 5 C2 — provenance
- **source_session**: <session-id>  # populated by hook when ADR is written by an agent; empty if human
- **last_verified**: YYYY-MM-DD    # when an owner last confirmed this is still the way; bumped by /adr-walk
- **Context**: link to the spec/plan/issue that triggered this decision
- **Tags**: architecture | data | api | security | infra | ux
- **Supersedes**: ADR-XXXX (if this replaces a prior decision)
- **superseded_by**:               # filled in when a future ADR replaces this one
- **orphaned_from**:               # Round 7 D — set if this ADR's parent initiative was abandoned/dropped. The technical claim may still be valid; the work that prompted it isn't. Extractor agent populates.

## Context

What is the issue we're seeing that motivates this decision? Cite evidence (file:line, log, ticket, doc URL).

## Decision

What is the change we're proposing? State it crisply.

## Alternatives considered

- **Option A** — pros / cons
- **Option B** — pros / cons
- **Option C** — pros / cons

## Consequences

- Positive: ...
- Negative: ...
- Neutral: ...

## Re-verification triggers

This ADR should be re-verified (and `last_verified:` bumped or `status:` flipped to `superseded`) when:

- A linked spec ships materially different behavior than what this ADR assumed.
- An incident in `.claude/memory/incidents/` touches the subsystem this ADR governs.
- A dependency this ADR depends on releases a major version with breaking changes.
- 12 months have elapsed since `last_verified:`.

`/adr-walk` surfaces ADRs that need attention.

## References

- Spec: specs/active/<id>-<slug>.md
- Plan: plans/active/<id>-<slug>.md
- Related ADRs: ADR-XXXX
- Incidents: .claude/memory/incidents/<file>.md  (if this ADR was informed by a past incident)
- External docs: <url>
