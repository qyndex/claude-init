---
name: 0000-incident-template
description: Postmortem template — copy to a new file and fill in.
metadata:
  type: incident
  status: template
---

# Incident: <One-line title>

- **Date**: YYYY-MM-DD
- **Severity**: SEV1 | SEV2 | SEV3
- **Status**: resolved | monitoring | open
- **Duration**: <start> → <end> (<duration>)
- **Authors**: <names>

## Summary

One paragraph: what happened, what was affected, how it was resolved.

## Timeline (all times UTC)

| Time | Event |
|---|---|
| HH:MM | First alert / user report |
| HH:MM | Diagnosis starts |
| HH:MM | Root cause identified |
| HH:MM | Mitigation applied |
| HH:MM | All-clear |

## Root cause

What was the actual cause? Cite the file:line, the commit, the misconfig, the bad assumption.

## Contributing factors

- Why didn't tests catch it?
- Why didn't monitoring catch it sooner?
- What gave us false signals?

## What went well

- ...

## What went poorly

- ...

## Action items

- [ ] <Owner, due date> — concrete preventive measure
- [ ] <Owner, due date> — improved monitoring/alerting
- [ ] <Owner, due date> — test that would have caught this

## Lessons for the agent

Plain-English rule for future Claude Code sessions:

> _Concrete, actionable rule. Example: "Never run a migration during peak hours; the rebuild lock blocks reads for 90+ seconds."_

This entry will be linked from `.claude/memory/MEMORY.md`.
