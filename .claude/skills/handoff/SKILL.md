---
name: handoff
description: Structured handoff between subagents, between background sessions, or between the night-run and the morning session. Uses the NEXUS YAML schema (v1.0). Required for swarm streams; recommended for all other subagents. Includes attempt counter, evidence requirement, explicit next-step.
when_to_use: A subagent finishes and reports back. A feature-stream session pauses for the coordinator. The night-run wraps up. User says "handoff", "status report", "what did you do".
model: inherit
---

# Handoff — NEXUS schema v1.0

A handoff is the **machine-parseable contract** between two agents/sessions. Round 6 D promotes the schema from optional markdown to required YAML with runtime validation on swarm streams.

## The canonical schema

Lives at [`.swarms/templates/handoff.yaml`](../../../.swarms/templates/handoff.yaml). The full template is 80+ lines; for routine handoffs you can omit optional sections (mark them as empty arrays/objects).

## How to emit a handoff

End your final message with a fenced block:

````markdown
```nexus
schema_version: "1.0"
task_id: T-042
parent_session_id: sess_abc123
subagent_id: sess_xyz789
subagent_name: researcher
status: completed
confidence: high
handoff_to: parent
summary: "Selected ioredis over node-redis; integration cost ~40 LOC."
artifacts_created:
  - path: docs/research/2026-05-28-cache-libs.md
    kind: research_brief
files_modified: []
files_read_but_not_modified:
  - src/cache/redis.ts
  - src/cache/memcached.ts
decisions_made:
  - decision: "Use ioredis"
    rationale: "active maintenance, native cluster"
    citations:
      - https://github.com/redis/ioredis
adrs_referenced: []
patterns_referenced: []
incidents_referenced: []
rejected_hypotheses: []
auto_fixed: []
tests_added: []
evidence_paths: []
verification_commands: []
blockers_encountered: []
open_questions: []
followup_tasks: []
tokens_used: 12400
cost_usd: 0.18
turns_used: 12
turns_max: 30
tool_calls: {bash: 3, read: 8, web_fetch: 4}
hook_blocks: []
classifier_denials: []
mcp_servers_used: []
```
````

Use ` ```nexus ` or ` ```yaml ` — the parser accepts both fence tags.

## Status taxonomy

| Status | When | Downstream effect |
|---|---|---|
| `completed` | Routine handoff between phases | Parent picks up next phase |
| `qa_pass` | Verification passed; ready for review/ship | reviewer / security / release agents triggered |
| `qa_fail` | Verification failed; needs fix | self-heal skill kicks in; attempt++ |
| `escalated` | 3 attempts failed; needs human | Stop loop; surface in OVERNIGHT_REPORT |
| `blocked` | External dep or decision required | Awaiting unblock; no further work |
| `aborted` | Operator stopped, OOM, classifier denied | No retry; surface why |

When `status: qa_pass`, `evidence_paths` MUST be populated (validator enforces).

## Enforcement (Round 6 D)

| Agent | Enforcement |
|---|---|
| feature-stream, coordinator | **HARD** — `subagent-stop.sh` parses the block; if missing or `validate-handoff.sh` exits non-zero, hook exits 2 (blocks) |
| architect, planner, implementer | **SOFT** — emit YAML; free prose accepted with a warning |
| reviewer, verifier, security | **SOFT** — emit YAML; `evidence_paths` required if QA-PASS-equivalent |
| debugger, researcher, doc-writer, tester | **SOFT** — emit YAML |

To soft-enforce → hard-enforce later: edit `.claude/hooks/subagent-stop.sh` and remove the agent from the "soft-fail" whitelist.

## Validate locally

```bash
# Validate a file
bash .claude/scripts/validate-handoff.sh path/to/handoff.yaml

# Validate stdin (e.g., a pasted block)
echo "$BLOCK" | bash .claude/scripts/validate-handoff.sh --stdin
```

## Hard rules

- **One handoff per logical milestone.** Phase boundaries (spec→plan, plan→implement, etc.). Don't write 10 per feature.
- **Cite, don't summarize.** Decisions reference commit SHAs or URLs with dates.
- **Attempt counter is real.** When self-heal retries, increment `attempt`. `attempt == max_attempts` → `status: escalated`.
- **Open questions are tracked.** They go into the parent spec's `[OQ]` list, not just here.
- **`followup_tasks` becomes TASKS.md entries.** `findings-to-tasks.sh` parses this list. Don't fake it.
- **AUTOPILOT degrade**: still emit the YAML; surface unresolved open_questions in OVERNIGHT_REPORT.md.

## Markdown-readable render

For human eyes, a renderer can convert the YAML to markdown — see [.swarms/templates/handoff.yaml](../../../.swarms/templates/handoff.yaml). The schema is the canonical form; markdown is a view.

## Where handoffs live

- Subagent → parent: fenced block in final message + persisted at `.swarms/streams/<id>/handoff-<ts>.yaml` (feature-stream)
- Feature stream → coordinator: `.swarms/streams/<id>/handoff-<ts>.yaml`
- Night run → morning: `OVERNIGHT_REPORT.md` with embedded NEXUS block
- PR description: copy the YAML block into the PR body inside `<details>`

## References

- Schema source: `.swarms/templates/handoff.yaml`
- Validator: `.claude/scripts/validate-handoff.sh`
- Parser hook: `.claude/hooks/subagent-stop.sh`
- Original NEXUS pattern: [msitarzewski/agency-agents](https://github.com/msitarzewski/agency-agents)
