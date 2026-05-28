---
description: Create a new skill from a description (or from instinct/signature evidence). Generates to .claude/memory.proposed/skills/ for review via /dream-review --approve-skill. Round 9 A.
argument-hint: "<slug> \"<description>\" [--examples <path,path>] [--triggers <phrase,phrase>]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /create-skill — Manual skill scaffold

Companion to `skill-creator` skill. Use when you (the operator) explicitly want a new skill — for auto-creation via observation, see `task-signature-detector.sh` and `/instinct promote --as-skill`.

```bash
slug="${1:-}"
description="${2:-}"
shift 2 2>/dev/null

examples=""
triggers=""
while [ $# -gt 0 ]; do
  case "$1" in
    --examples) examples="$2"; shift 2 ;;
    --triggers) triggers="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$slug" ] || [ -z "$description" ]; then
  echo "Usage: /create-skill <slug> \"<description starting with 'Use when…'>\" [--examples p1,p2] [--triggers t1,t2]"
  exit 1
fi

# Validate slug
if ! echo "$slug" | grep -qE '^[a-z][a-z0-9-]{0,31}$'; then
  echo "Slug must be kebab-case, lowercase, ≤ 32 chars: $slug"
  exit 1
fi

# Refuse if a skill or proposed skill with this slug exists
if [ -d ".claude/skills/$slug" ]; then
  echo "Skill .claude/skills/$slug already exists. Pick a different slug or edit the existing one."
  exit 1
fi
if [ -d ".claude/memory.proposed/skills/$slug" ]; then
  echo "Proposed skill .claude/memory.proposed/skills/$slug already exists. Approve/discard first."
  exit 1
fi

# Per-day cap
today=$(date +%Y-%m-%d)
counter_file=".claude/memory/.cache/skill-create-count-${today}"
mkdir -p "$(dirname "$counter_file")"
count=$(cat "$counter_file" 2>/dev/null || echo 0)
if [ "$count" -ge 3 ]; then
  echo "Daily skill-creation cap reached (3/day). Try tomorrow or remove the rate-limit via env."
  exit 1
fi

# Spawn skill-creator (uses the local skill)
echo "→ Invoking skill-creator for $slug"
if command -v claude >/dev/null 2>&1; then
  claude -p --max-turns 10 --max-budget-usd 1.00 \
    --append-system-prompt "Use .claude/skills/skill-creator/SKILL.md. Inputs: slug='$slug', description='$description', examples='$examples', triggers='$triggers'. Write to .claude/memory.proposed/skills/$slug/. Emit NEXUS YAML handoff." \
    "Create skill $slug" 2>&1 | tail -50
fi

# Increment counter
echo $((count + 1)) > "$counter_file"

if [ -d ".claude/memory.proposed/skills/$slug" ]; then
  echo
  echo "✓ Proposed skill at .claude/memory.proposed/skills/$slug/"
  echo
  echo "Next: review and approve"
  echo "  cat .claude/memory.proposed/skills/$slug/SKILL.md"
  echo "  /dream-review --approve-skill $slug"
  echo
  echo "Or discard:"
  echo "  /dream-review --revert-skill $slug"
fi
```

## Hard rules

- **Never bypass the validation gate.** skill-creator runs the full validation table; don't shortcut.
- **The proposal is NOT active.** Until `/dream-review --approve-skill <slug>`, it lives only in `.claude/memory.proposed/skills/` and won't be auto-invoked.
- **Per-day cap 3.** Prevents accidental skill bloat.

$ARGUMENTS
