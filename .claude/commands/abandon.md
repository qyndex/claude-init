---
description: Abandon an initiative with full retained-learnings extraction. Runs the extractor agent to produce a post-mortem + anti-patterns + ADR patches + salvage tasks + sunk-cost report before archiving. Round 7 D.
argument-hint: "<initiative-id> --reason <text> [--evidence <url-or-path>]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, TodoWrite
disable-model-invocation: true
---

# /abandon — Initiative-level abandonment with learning extraction

Use when an initiative is being killed (not paused, not superseded). Distinct from `/pivot drop` (which is fast and cascades) — `/abandon` is the **deep** version that spends time extracting what survives before the files move to archive.

When in doubt:
- `/pivot drop` → "we're done with this; cascade the status changes"
- `/abandon` → "we're done with this; before archiving, extract every drop of value"

You usually run BOTH. `/pivot drop` does the cascade fast; `/abandon` does the post-mortem deep.

## Syntax

```bash
/abandon <initiative-id> --reason "<text>" [--evidence <url-or-path>]
```

## Implementation

```bash
id="${1:-}"
shift 2>/dev/null
reason=""
evidence=""
while [ $# -gt 0 ]; do
  case "$1" in
    --reason) reason="$2"; shift 2 ;;
    --evidence) evidence="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$id" ] || [ -z "$reason" ]; then
  echo "Usage: /abandon <initiative-id> --reason \"<text>\" [--evidence <url>]"
  exit 1
fi

# 1. Validate initiative exists
init_file=$(ls initiatives/active/${id}*.md initiatives/active/*-${id}*.md 2>/dev/null | head -1)
if [ -z "$init_file" ]; then
  echo "Initiative not found in active/: $id"
  echo "Run /pivot drop $id first if it's still active."
  exit 1
fi

echo "→ /abandon $id"
echo "  Reason: $reason"
echo "  Initiative: $init_file"
echo

# 2. Run cost-report to get sunk cost FIRST (before files move)
echo "→ Computing sunk cost..."
bash .claude/scripts/cost-report.sh month --by-initiative "$id"

# 3. Spawn extractor agent — Opus, hard thinking
echo
echo "→ Spawning extractor agent for retained-learnings analysis..."
echo "  (this takes a few minutes — extractor reads child specs, plans, ADRs, git log, feedback)"

claude -p --max-turns 50 --max-budget-usd 5 \
  --agent extractor \
  --append-system-prompt "Initiative being abandoned: $id at $init_file. Reason: $reason. Evidence: $evidence. Extract retained learnings per .claude/agents/specialists/extractor.md mandate. Emit NEXUS YAML handoff." \
  "Extract retained learnings for abandoned initiative $id" 2>&1 | tee ".claude/hooks/.log/abandon-${id}-$(date +%Y%m%d-%H%M%S).log"

# 4. Verify post-mortem was created
post_mortem=$(ls .claude/memory/post-mortems/${id}-*.md 2>/dev/null | head -1)
if [ -z "$post_mortem" ]; then
  echo "⚠ Extractor did not produce a post-mortem. Check log."
  echo "  /abandon is incomplete — re-run or manually create the post-mortem before /quarterly-archive can pick this up."
  exit 1
fi

echo
echo "  ✓ Post-mortem: $post_mortem"

# 5. Update initiative status to abandoned (if not already)
sed -i.bak "s/^status:[[:space:]]*[a-z]*/status: abandoned/" "$init_file" && rm -f "${init_file}.bak"

# 6. Append abandonment record to .swarms/coordinator/decisions.log
echo "$(date -Iseconds) ABANDON initiative=$id reason=\"$reason\" post_mortem=$post_mortem" \
  >> .swarms/coordinator/decisions.log

# 7. Surface to operator
echo
echo "✓ /abandon complete"
echo
echo "  Initiative: $init_file (status → abandoned)"
echo "  Post-mortem: $post_mortem"
echo "  Sunk cost: .claude/memory/audits/sunk-cost-${id}-$(date +%Y-%m-%d).md"
echo
echo "Next:"
echo "  1. Review the post-mortem — fill in any blanks the extractor couldn't"
echo "  2. Get peer-review sign-off on the post-mortem"
echo "  3. Communicate to stakeholders (Slack/email)"
echo "  4. After 30 days, /quarterly-archive moves the initiative + post-mortem to archive/"
echo "     (refuses to archive abandoned initiatives without a post-mortem — Round 7 D enforcement)"
echo "  5. Code salvage tasks added to tasks/TASKS.md with priority: cleanup"
```

## Why /abandon and /pivot drop are separate

- `/pivot drop` is **lightweight** and **fast**: cascade statuses, stop streams, write pivot manifest. Use mid-meeting when leadership says "kill it."
- `/abandon` is **heavyweight** and **slow**: spawn extractor agent (Opus, $5 budget, up to 50 turns), read everything, write a post-mortem, patch ADRs, generate salvage tasks. Use AFTER the dust settles.

Typical sequence:
```
Mon  /pivot drop INIT-037 --reason "market shifted; deprioritizing"
       → fast cascade, fleet stops, manifest written
       → child specs flipped to status: dropped
Wed  /abandon INIT-037 --reason "..." --evidence <pivot manifest>
       → extractor reads everything
       → post-mortem written
       → anti-patterns extracted
       → salvage tasks queued
```

## Quarterly archive enforcement (Round 7 D)

The `quarterly-archive.yml` routine refuses to archive an `abandoned` initiative if no post-mortem exists. This forces the discipline — you can't "just delete it" — the learning extraction is mandatory.

To override (e.g., genuinely no learnings worth extracting), you must record a
**reviewed** decision — a one-line stub is rejected by the archive gate (Round 13 Fix 3).
The override file needs a `reviewed_by:` naming a human who is **not** the author, plus an
`override_reason:`:

```bash
cat > .claude/memory/post-mortems/<id>-skip.md <<'EOF'
---
override: true
override_reason: "Spike only; no production code shipped, no decisions to preserve."
reviewed_by: "@teammate-who-signed-off"   # NOT the person abandoning it
reviewed_at: 2026-05-28
---
# <id> — extraction skipped (reviewed override)
Why no post-mortem is warranted: <2-3 sentences>.
EOF
```

The gate (`quarterly-archive.yml`) accepts a post-mortem only if it has real content
(≥ 20 non-blank lines — a genuine extractor output) **or** carries `reviewed_by:`. That
makes "skip the learning" a deliberate, attributable choice rather than a silent `echo`.

## Hard rules

- **Reason is required.** No --reason → command refuses.
- **Initiative must be in active/.** If it's already archived, /abandon errors out (manifest must exist for retrospection).
- **Extractor uses Opus.** This is genuinely hard work; cost of $5/abandonment is small vs. value preserved.
- **Don't archive without a post-mortem.** Quarterly-archive enforces.

$ARGUMENTS
