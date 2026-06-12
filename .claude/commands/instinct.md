---
description: Manage the continuous-learning instinct store — list active instincts, force an extraction pass, promote project→global, archive. Backs the /instinct commands documented in .claude/skills/instinct/SKILL.md (gap-audit G26 — this file previously did not exist).
argument-hint: "<list|extract|promote <id> [--as-skill]|archive <id>>"
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
disable-model-invocation: true
---

# /instinct — continuous-learning store management

```bash
sub="${1:-list}"
id="${2:-}"

case "$sub" in
  list)
    if [ -s .claude/memory/instincts/active.yml ]; then
      echo "# Active instincts (sorted by confidence)"
      cat .claude/memory/instincts/active.yml
    else
      echo "No active instincts yet."
      obs=$(wc -l < .claude/memory/.cache/instincts/observations.jsonl 2>/dev/null | tr -d ' ')
      echo "Observations accumulated: ${obs:-0} — extraction runs automatically at ≥50 new (auto-dream-check), or force with: /instinct extract"
    fi
    echo
    echo "# Global store"
    bash .claude/scripts/instinct-promote.sh list
    ;;
  extract)
    bash .claude/scripts/instinct-extract.sh --force
    echo "Extraction spawned (Haiku, background) — check .claude/hooks/.log/instinct.log"
    ;;
  promote)
    [ -z "$id" ] && { echo "Usage: /instinct promote <id> [--as-skill]"; exit 1; }
    if [ "${3:-}" = "--as-skill" ]; then
      echo "Materializing instinct '$id' as a skill proposal — follow .claude/skills/skill-creator/SKILL.md with the instinct's trigger/action as seed; write to .claude/memory.proposed/skills/<slug>/."
    else
      bash .claude/scripts/instinct-promote.sh promote "$id"
    fi
    ;;
  archive)
    [ -z "$id" ] && { echo "Usage: /instinct archive <id>"; exit 1; }
    # Move the entry block from active.yml to archive.yml
    if [ -s .claude/memory/instincts/active.yml ]; then
      awk -v want="$id" '
        /^- id:/ { inb = ($0 ~ "- id:[[:space:]]*\"?" want) }
        inb { print > ".claude/memory/instincts/archive.yml.part"; next }
        { print }
      ' .claude/memory/instincts/active.yml > .claude/memory/instincts/active.yml.tmp
      mv .claude/memory/instincts/active.yml.tmp .claude/memory/instincts/active.yml
      [ -f .claude/memory/instincts/archive.yml.part ] && cat .claude/memory/instincts/archive.yml.part >> .claude/memory/instincts/archive.yml && rm -f .claude/memory/instincts/archive.yml.part
      echo "✓ archived $id"
    fi
    ;;
  *)
    echo "Usage: /instinct <list|extract|promote <id> [--as-skill]|archive <id>>"
    ;;
esac
```

$ARGUMENTS
