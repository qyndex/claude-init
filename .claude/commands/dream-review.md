---
description: Review pending /dream consolidations or skill proposals before they activate. Shows diff; user approves or reverts. Round 9 A adds --approve-skill/--revert-skill for proposed skills under .claude/memory.proposed/skills/.
argument-hint: "[--revert] [--approve] [--approve-skill <slug>] [--revert-skill <slug>]"
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
disable-model-invocation: true
---

# /dream-review — Supervise the consolidator

`/dream` consolidates memory in the background. Before its changes land in `.claude/memory/`, review the diff here.

```bash
mode="${1:-show}"   # show | --approve | --revert

PROPOSED=".claude/memory.proposed"
CANONICAL=".claude/memory"

case "$mode" in
  show|"")
    if [ ! -d "$PROPOSED" ]; then
      echo "No pending dream consolidation. Either:"
      echo "  - /dream hasn't run yet, OR"
      echo "  - The last dream was already approved"
      exit 0
    fi
    echo "# Dream review — proposed consolidation"
    echo
    echo "Generated: $(date -r "$PROPOSED" -Iseconds 2>/dev/null || stat -f %SB "$PROPOSED")"
    echo
    echo "## Diff (canonical → proposed)"
    diff -r "$CANONICAL" "$PROPOSED" || true
    echo
    echo "Decision:"
    echo "  /dream-review --approve   → apply (canonical = proposed; archive)"
    echo "  /dream-review --revert    → discard proposed"
    ;;

  --approve)
    if [ ! -d "$PROPOSED" ]; then
      echo "Nothing to approve."
      exit 0
    fi
    # Archive current canonical
    archive_dir=".claude/memory/.archive/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$archive_dir"
    cp -r "$CANONICAL"/* "$archive_dir/" 2>/dev/null || true
    # Apply proposed
    rm -rf "$CANONICAL"
    mv "$PROPOSED" "$CANONICAL"
    echo "✓ Dream consolidation applied; previous state archived to $archive_dir"
    ;;

  --revert)
    if [ ! -d "$PROPOSED" ]; then
      echo "Nothing to revert."
      exit 0
    fi
    rm -rf "$PROPOSED"
    echo "✓ Proposed consolidation discarded; canonical memory unchanged"
    ;;

  --approve-skill)
    # Round 9 A: approve a proposed skill from .claude/memory.proposed/skills/<slug>/
    slug="${2:-}"
    [ -z "$slug" ] && { echo "Usage: /dream-review --approve-skill <slug>"; exit 1; }
    src=".claude/memory.proposed/skills/$slug"
    [ ! -d "$src" ] && { echo "No proposed skill at $src"; exit 1; }
    [ -d ".claude/skills/$slug" ] && { echo "Skill .claude/skills/$slug already exists; remove first or pick different slug"; exit 1; }

    # Final validations before activating
    if ! grep -qE '^name: ' "$src/SKILL.md"; then echo "Invalid: missing 'name:' frontmatter"; exit 1; fi
    if ! grep -qE '^description: ' "$src/SKILL.md"; then echo "Invalid: missing 'description:'"; exit 1; fi
    if ! grep -qE '^when_to_use: ' "$src/SKILL.md"; then echo "Invalid: missing 'when_to_use:'"; exit 1; fi
    if command -v gitleaks >/dev/null; then
      gitleaks detect --no-banner --no-git --source "$src" --redact -q 2>/dev/null || { echo "Invalid: gitleaks detected secrets in skill body"; exit 1; }
    fi

    mv "$src" ".claude/skills/$slug"
    echo "✓ Skill .claude/skills/$slug activated"
    echo "  Next: it will appear in skill listings on next session; manual test via the skill's example invocations"
    ;;

  --revert-skill)
    slug="${2:-}"
    [ -z "$slug" ] && { echo "Usage: /dream-review --revert-skill <slug>"; exit 1; }
    src=".claude/memory.proposed/skills/$slug"
    [ ! -d "$src" ] && { echo "No proposed skill at $src"; exit 0; }
    rm -rf "$src"
    echo "✓ Proposed skill $slug discarded"
    ;;
esac
```

## How /dream now writes

After this batch, the dream skill no longer writes directly to `.claude/memory/`. It writes to `.claude/memory.proposed/`. Operator then `/dream-review` → `/dream-review --approve` (or `--revert`).

This closes the audit finding: dream consolidation had no review gate → bad consolidation undetectable.

$ARGUMENTS
