---
description: Strategic pivot orchestrator. Drop, pause, supersede, or stop a feature/spec/initiative mid-flight with full cascade — stops streams, marks tasks, writes pivot manifest, preserves WIP, logs decision. Round 7 A.
argument-hint: "<verb> <id> [--reason <text>] [--by <new-id>] [--until <date>] [--evidence <url>]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, TodoWrite, AskUserQuestion
disable-model-invocation: true
---

# /pivot — Strategic pivot orchestrator

When the market shifts, customer feedback demands a reset, or leadership picks a new direction mid-execution. **One command** to cascade the change across spec → plan → tasks → swarm → ADR → decision log → roadmap.

## Verbs

| Verb | When | What it does |
|---|---|---|
| `drop` | Feature is dead. Won't pick up. | Status→dropped on spec+plan; cascade tasks to `[s]` with reason; stop running streams; archive worktree; write pivot manifest; surface salvage candidates |
| `pause` | Right idea, wrong time. Resume later. | Status→paused on spec+plan+initiative; tasks to `[b]` with `blocked_by: PIV-<id>`; commit WIP with PAUSED marker; preserve worktree |
| `supersede` | New direction replaces old (continuity). | Old.status=superseded, new.status=approved; link bidirectionally; carry over surviving ADRs; close old KRs, attach to new |
| `stop` | Pivot decision pending; halt all in-flight work | See [/pivot stop](#pivot-stop) — listed separately. Batch E. |

## Syntax

```bash
/pivot drop <spec-or-initiative-id> --reason "<text>" [--evidence <url-or-path>]
/pivot pause <id> --until <YYYY-MM-DD> [--reason "<text>"]
/pivot supersede <old-id> --by <new-id> [--reason "<text>"]
/pivot stop <reason-or-new-initiative-id>      # see batch E
```

## Behavior — implementation

```bash
verb="${1:-}"
target="${2:-}"
reason=""
by=""
until_date=""
evidence=""

shift 2 2>/dev/null
while [ $# -gt 0 ]; do
  case "$1" in
    --reason) reason="$2"; shift 2 ;;
    --by) by="$2"; shift 2 ;;
    --until) until_date="$2"; shift 2 ;;
    --evidence) evidence="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

case "$verb" in
  drop|pause|supersede|stop) ;;
  *) echo "Usage: /pivot drop|pause|supersede|stop <id> ..."; exit 1 ;;
esac

if [ "$verb" = "stop" ]; then
  exec bash .claude/scripts/pivot-stop.sh "$target"
fi

# Resolve target: is it a spec, plan, or initiative?
artifact=""
artifact_kind=""
for kind in initiatives specs plans; do
  for file in "${kind}/active/${target}"*.md "${kind}/active/${target}-"*.md; do
    if [ -f "$file" ]; then
      artifact="$file"
      artifact_kind="$kind"
      break 2
    fi
  done
done

if [ -z "$artifact" ]; then
  echo "Target not found: $target"
  exit 1
fi

echo "→ pivot $verb on $artifact"

# 1. Generate pivot manifest ID (PIV-NNN)
mkdir -p pivots/active
last_id=$(ls pivots/active/PIV-*.md pivots/archive/PIV-*.md 2>/dev/null | grep -oE 'PIV-[0-9]+' | sort -t- -k2 -n | tail -1 | grep -oE '[0-9]+' || echo 0)
piv_id="PIV-$(printf '%03d' $((last_id + 1)))"

# 2. Cascade status changes
case "$verb" in
  drop)
    new_status="dropped"
    # Cascade: target + every child whose frontmatter points at this initiative
    sed -i.bak "s/^status:[[:space:]]*[a-z]*/status: $new_status/" "$artifact" && rm -f "${artifact}.bak"
    if [ "$artifact_kind" = "initiatives" ]; then
      # find specs with initiative: <id>
      init_id=$(grep -E '^id:' "$artifact" | head -1 | sed 's/id:[[:space:]]*//')
      for child in specs/active/*.md plans/active/*.md; do
        [ -f "$child" ] || continue
        if grep -qE "^initiative:[[:space:]]*${init_id}\\b" "$child" 2>/dev/null; then
          sed -i.bak "s/^status:[[:space:]]*[a-z]*/status: $new_status/" "$child" && rm -f "${child}.bak"
          echo "  cascade: dropped $child"
        fi
      done
    fi
    # Cascade tasks: anything referencing the target's spec/plan id → [s]
    target_id=$(basename "$artifact" .md | grep -oE '^[A-Z]*-?[0-9]+' || echo "")
    if [ -n "$target_id" ] && [ -f tasks/TASKS.md ]; then
      sed -i.bak -E "s/^- \\[ \\]([^|]*\\|[^|]*spec:${target_id})/- [s]\\1 | pivot:$piv_id/g" tasks/TASKS.md
      rm -f tasks/TASKS.md.bak
    fi
    ;;
  pause)
    new_status="paused"
    sed -i.bak "s/^status:[[:space:]]*[a-z]*/status: $new_status/" "$artifact" && rm -f "${artifact}.bak"
    # Note: spec template gained `paused` status in Round 7 A
    ;;
  supersede)
    if [ -z "$by" ]; then echo "supersede requires --by <new-id>"; exit 1; fi
    sed -i.bak "s/^status:[[:space:]]*[a-z]*/status: superseded/" "$artifact" && rm -f "${artifact}.bak"
    if ! grep -q '^superseded_by:' "$artifact"; then
      printf '\nsuperseded_by: %s\n' "$by" >> "$artifact"
    else
      sed -i.bak "s|^superseded_by:.*|superseded_by: $by|" "$artifact" && rm -f "${artifact}.bak"
    fi
    ;;
esac

# 3. Stop any running swarm streams under this artifact
if [ -f .swarms/coordinator/fleet.json ] && command -v jq >/dev/null; then
  running=$(jq -r '.fleet | to_entries[] | select(.value.status == "running") | .key' .swarms/coordinator/fleet.json)
  for s in $running; do
    # Best-effort: stop streams whose brief mentions this artifact
    if [ -f ".swarms/streams/$s/brief.md" ] && grep -q "$target" ".swarms/streams/$s/brief.md" 2>/dev/null; then
      echo "  stopping stream $s (mentions $target)"
      # delegate to /swarm:stop if available; else mark in fleet
      jq --arg s "$s" --arg piv "$piv_id" --arg r "$reason" \
        '.fleet[$s].status = "stopped_for_pivot" | .fleet[$s].pivot_id = $piv | .fleet[$s].stop_reason = $r' \
        .swarms/coordinator/fleet.json > /tmp/f && mv /tmp/f .swarms/coordinator/fleet.json
    fi
  done
fi

# 4. Write pivot manifest
piv_file="pivots/active/${piv_id}-$(echo "$target" | head -c 32).md"
cat > "$piv_file" <<EOF
---
id: $piv_id
date: $(date -Iseconds)
verb: $verb
target: $target
target_kind: $artifact_kind
target_path: $artifact
superseded_by: $by
pause_until: $until_date
evidence: $evidence
new_status: ${new_status:-$verb}
written_by: pivot-command
---

# Pivot $piv_id: $verb $target

## Trigger
$reason

## Pivot type
<one of: zoom-in | zoom-out | customer-segment | customer-need | platform | business-architecture | value-capture | engine-of-growth | channel | technology | tactical-correction>

## Old direction
<what we were doing — pulled from $artifact summary>

## New direction
$( [ -n "$by" ] && echo "Replaced by $by" || echo "Stopped without successor" )

## Sunk cost
_(Populated by cost-report.sh --by-initiative once integrated with current-initiative state.)_

## Retained learnings
_(Populated by extractor agent — see /abandon for the deep version.)_

## Affected
- Target: $artifact
- Streams stopped: $(echo $running | tr ' ' ',')
- Pivot manifest: $piv_file

## Peer review
_(Required: one reviewer signoff before this pivot is irreversible.)_

## References
- Decision log entry: .swarms/coordinator/decisions.log (this timestamp)
- See related ADRs via: \`grep -l '$target' .claude/memory/decisions/\`
EOF

# 5. Log decision
mkdir -p .swarms/coordinator
echo "$(date -Iseconds) $piv_id PIVOT verb=$verb target=$target reason=\"$reason\" by=\"$by\"" >> .swarms/coordinator/decisions.log

# 6. Surface to operator
echo
echo "✓ Pivot $piv_id created at $piv_file"
echo
echo "  Target: $artifact (status → ${new_status:-$verb})"
echo "  Reason: $reason"
[ -n "$by" ] && echo "  Replaced by: $by"
[ -n "$until_date" ] && echo "  Pause until: $until_date"
echo
echo "Next:"
echo "  1. Review $piv_file — fill in Pivot type + Old/New direction"
echo "  2. Get peer review signoff"
[ "$verb" = "drop" ] && echo "  3. Run /abandon $target for retained-learnings extraction (Batch D)"
[ "$verb" = "drop" ] && echo "  4. Run bash .claude/scripts/cost-report.sh --by-initiative $target for sunk-cost report (Batch E)"
echo "  5. Update roadmap.md if this affects Now/Next/Later placement"
```

## Hard rules

- **Pivot is reversible only as another pivot.** If you /pivot drop X and want it back, /pivot create-from-archive X (not implemented; manual restore).
- **The manifest is the audit trail.** Every pivot creates a PIV-NNN file. Don't bypass.
- **Cascade is opt-in for cross-team.** Drop on an initiative cascades to its specs; drop on a spec does NOT cascade up.
- **Reason is required.** No --reason → command refuses.
- **AUTOPILOT**: in autopilot context, /pivot drop refuses unless `--evidence` is also provided. Cancelling work autonomously is too dangerous.

## Related

- `/abandon <id>` — Batch D — runs extractor agent for "what we learned"
- `/pivot stop` — Batch E — halts in-flight work pending a pivot decision
- `/spec pause <id> --until <date>` — Batch A — pause without full pivot ceremony
- `/roadmap demote <id>` — Batch A — Now→Next or Next→Later
- `/initiative supersede <id> --by <new>` — Batch A — implementation of long-documented command

$ARGUMENTS
