---
description: For each stream reporting status=qa_pass (NEXUS YAML), run verified-merge.sh (rebase onto siblings → integration test → AI-mediated semantic conflict resolution → merge → post-merge verify with auto-revert). Refuses flat merge.
argument-hint: "[--only feat-001] [--auto-confirm] (auto-confirm requires human-token)"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, TodoWrite
disable-model-invocation: true
---

# /swarm:merge — Verified merge for PASS streams

Round 6 E. Replaces flat squash-merge with `verified-merge.sh` (5-step protocol).

```bash
# For each stream whose latest handoff has status=qa_pass (parsed from NEXUS YAML):

# Topological order — process streams that own shared files BEFORE streams that consume them
# (currently heuristic: first-pass-first-merged; replace with `analysis.md` deps graph in a future round)

for stream in $(ls .swarms/streams/); do
  handoff=$(ls -t .swarms/streams/$stream/handoff-final-*.yaml 2>/dev/null | head -1)
  [ -z "$handoff" ] && continue

  # Parse NEXUS YAML status — NOT grep for "QA-PASS"
  status=$(yq eval '.status' "$handoff" 2>/dev/null || grep -E '^status:' "$handoff" | head -1 | sed 's/status: //')

  case "$status" in
    qa_pass)
      # Run the 5-step verified merge protocol:
      # 1. Rebase onto main + already-merged siblings
      # 2. Integration test (verify.sh + local-pr-check --heavy + contract-tests)
      # 3. AI-mediated semantic conflict resolution (if step 2 fails)
      # 4. Merge (squash to main)
      # 5. Post-merge verify; auto-revert + auto-fix PR on failure
      bash .claude/scripts/verified-merge.sh "$stream"
      ;;
    escalated|qa_fail)
      gh issue create \
        --title "Stream $stream: $status" \
        --body "$(cat "$handoff")" \
        --label "swarm,escalation"
      jq --arg s "$stream" '.fleet[$s].status = "escalated"' .swarms/coordinator/fleet.json \
        > .swarms/coordinator/.fleet.json.tmp.$$ && mv .swarms/coordinator/.fleet.json.tmp.$$ .swarms/coordinator/fleet.json
      ;;
    blocked)
      jq --arg s "$stream" '.fleet[$s].status = "blocked"' .swarms/coordinator/fleet.json \
        > .swarms/coordinator/.fleet.json.tmp.$$ && mv .swarms/coordinator/.fleet.json.tmp.$$ .swarms/coordinator/fleet.json
      ;;
    *)
      echo "  ? unknown status '$status' for stream $stream — skipping"
      ;;
  esac
done

# Also: parse each handoff's followup_tasks and append to TASKS.md
for stream in $(ls .swarms/streams/); do
  handoff=$(ls -t .swarms/streams/$stream/handoff-final-*.yaml 2>/dev/null | head -1)
  [ -z "$handoff" ] && continue
  bash .claude/scripts/findings-to-tasks.sh "$handoff" \
    --priority normal \
    --source "swarm:$stream"
done
```

## Hard rules

- **Never flat-merge.** `gh pr merge --auto --squash` without rebasing onto verified siblings is the old (broken) flow. Use `verified-merge.sh`.
- **status comes from YAML, not prose.** If the handoff lacks a parseable `status:` field, treat it as if missing — refuse to merge.
- **Auto-revert is on by default.** Post-merge `verify.sh` failure → revert + spawn auto-fix PR. The decision is logged in `.swarms/coordinator/decisions.log`.
- **Contract-tests catch semantic deps.** Streams declare what they consume in `analysis.md`. If a contract is missing on the integrated branch, mediation fires.
- **Mediation has a budget**: max 30 turns / $2 / 1 commit. If mediation can't fix it, the merge fails — human review required.

## Post-merge

- Worktree removal is handled inside `verified-merge.sh`.
- `fleet.json` updated to `_schema_version: 2` with `merged_at`, `mediation_used`, optional `reverted_at`.
- `decisions.log` appended.

## Output

```
N merged | M mediated | K reverted | L escalated | P blocked
```

`/swarm:status` shows the current state. `/dream` consolidates memory once all streams are done.

$ARGUMENTS
