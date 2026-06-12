---
name: 0001-sonnet-default-model-routing
description: "ADR-0001: Sonnet-by-default model routing; Opus reserved for hard-thinking agents (Round 5)"
status: accepted
created: 2026-05-20
metadata:
  type: decision
  status: accepted
---

# ADR-0001: Sonnet-by-default model routing; Opus reserved for hard-thinking agents

- **Status**: accepted
- **Date**: 2026-05-20
- **Deciders**: @shravanjha
- **Owners**: [@shravanjha]
- **written_by**: human
- **source_session**:
- **last_verified**: 2026-06-12
- **Context**: Round 5 cost audit (docs/RESEARCH.md cost-routing section); .claude/CLAUDE.md §V
- **Tags**: architecture
- **subsystem**: model-routing
- **Supersedes**:
- **superseded_by**:
- **orphaned_from**:

## Context

The Round 5 audit found orchestration agents (planner, coordinator, feature-stream,
verifier, release) running on Opus while their transcripts showed short, mechanical
interactions — schema-following, DAG-walking, command execution — not hard reasoning.
Opus spend dominated the monthly cap without measurable quality gain on those roles.

## Decision

Default every agent to **Sonnet** unless its role demonstrably needs hard thinking
or high craft. Opus is reserved for: architect, implementer, reviewer, security,
debugger, designer, extractor. Haiku serves retrieval-only (`Explore`). The routing
table in `.claude/CLAUDE.md §V` is authoritative; every agent's frontmatter `model:`
must match it (checked in review; see also ADR-0002's evidence-gate pattern).

## Alternatives considered

- **Opus everywhere** — best raw capability; rejected: 3-5× cost with no measured gain on mechanical roles.
- **Haiku for orchestration** — cheapest; rejected: coordinator/feature-stream need reliable schema adherence under long contexts, where Haiku regressed in Round 5 testing.
- **Dynamic per-task routing** — ideal long-term; rejected for now: no reliable per-task difficulty signal exists yet (see learn-from-success.sh routing insights — heuristic only).

## Consequences

- Positive: ~60% projected reduction in autonomous-loop spend; cap headroom for swarms.
- Negative: occasional quality dip on borderline tasks (planner decomposition); mitigated by Opus implementer/reviewer downstream.
- Neutral: routing table becomes a maintained artifact (constitution §V + frontmatter must stay in sync).

## Re-verification triggers

- A new model generation ships (e.g., Fable/Mythos-class becomes available for routing).
- learn-from-success.sh routing insights show a Sonnet agent repeatedly failing verification.
- 12 months elapse since `last_verified:`.

## References

- .claude/CLAUDE.md §V (authoritative table)
- docs/RESEARCH.md (cost-routing research)
- Related: ADR-0002 (verification gates), ADR-0003 (issue projection)
