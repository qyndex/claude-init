#!/usr/bin/env bash
# Reconcile the factory .claude/ into a brownfield repo that already has its own. Round 14.
#
# `cp -nr .claude` is FORBIDDEN for a populated .claude/ — no-clobber leaves a frankenstein
# half-merge. This reconciler uses three buckets and NEVER silent-merges:
#   • factory-authoritative (process/orchestration) → overwrite, but BACK UP first
#   • never-overwrite (their knowledge + secrets + local state) → preserve verbatim
#   • merge-by-extraction (their conventions) → extracted to AGENTS.md by extract-conventions.sh
# Every direct conflict becomes an [OQ] in ADOPTION-REPORT.md routed through /clarify.
# Fully reversible: originals are copied to .claude/.brownfield-backup/<ts>/ before anything.
#
# Runs from anywhere (does NOT use the script-relative ROOT — it operates on --into):
#   reconcile-claude-dir.sh --from <factory-clone-dir> [--into <repo-dir>] [--dry-run]

set -uo pipefail
FROM=""; INTO="$(pwd)"; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --from) FROM="${2:-}"; shift 2 ;;
  --into) INTO="${2:-}"; shift 2 ;;
  --dry-run) DRY=1; shift ;;
  *) shift ;;
esac; done

[ -z "$FROM" ] && { echo "usage: reconcile-claude-dir.sh --from <factory-clone-dir> [--into <repo>] [--dry-run]"; exit 1; }
[ -d "$FROM/.claude" ] || { echo "no .claude/ found in factory dir: $FROM"; exit 1; }
cd "$INTO" 2>/dev/null || { echo "cannot cd into target: $INTO"; exit 1; }

ts="$(date +%Y%m%d-%H%M%S)"
BK=".claude/.brownfield-backup/$ts"
REPORT="ADOPTION-REPORT.md"
# Factory owns PROCESS. These dirs/files are overwritten (after backup).
FACTORY_DIRS="agents skills commands hooks scripts routines statuslines output-styles"
FACTORY_FILES="CLAUDE.md settings.json"

run() { [ "$DRY" = 1 ] && echo "[dry-run] $*" || eval "$*"; }

# ── Greenfield fast-path: no existing .claude/ → plain copy ───────────────
if [ ! -d .claude ]; then
  echo "→ No existing .claude/ in $INTO — greenfield copy (no reconciliation needed)."
  run "cp -r '$FROM/.claude' .claude"
  echo "✓ copied factory .claude/. Run: bash .claude/scripts/setup.sh"
  exit 0
fi

echo "→ Existing .claude/ found in $INTO — reconciling (3 buckets, never silent-merge)."
run "mkdir -p '$BK'"
run "cp -R .claude/. '$BK/' 2>/dev/null || true"
echo "  backed up your original .claude/ → $BK"

# Preserve their CLAUDE.md if it is NOT already the factory's (signature check).
conflict_claude=""
if [ -f .claude/CLAUDE.md ] && ! grep -q "Karpathy's Four Principles" .claude/CLAUDE.md 2>/dev/null; then
  run "cp .claude/CLAUDE.md .claude/CLAUDE.md.brownfield-orig"
  conflict_claude=1
  echo "  preserved your CLAUDE.md → .claude/CLAUDE.md.brownfield-orig"
fi
# Preserve their settings.json (custom permissions) before the factory's overwrites it.
conflict_settings=""
if [ -f .claude/settings.json ] && ! grep -q "disableBypassPermissionsMode" .claude/settings.json 2>/dev/null; then
  run "cp .claude/settings.json .claude/settings.json.brownfield-orig"
  conflict_settings=1
fi

# Copy factory-authoritative dirs (factory files win; their extra files remain).
for d in $FACTORY_DIRS; do
  [ -d "$FROM/.claude/$d" ] || continue
  run "mkdir -p '.claude/$d'"
  run "cp -R '$FROM/.claude/$d/.' '.claude/$d/'"
done
for f in $FACTORY_FILES; do
  [ -f "$FROM/.claude/$f" ] && run "cp '$FROM/.claude/$f' '.claude/$f'"
done

# Extract their conventions into AGENTS.md + a project-conventions rule (human refines).
if [ -f "$FROM/.claude/scripts/extract-conventions.sh" ]; then
  run "bash '$FROM/.claude/scripts/extract-conventions.sh' --into '$INTO'"
fi

# Append the collision map + [OQ]s to the adoption report.
if [ "$DRY" = 0 ]; then
  {
    echo
    echo "## Existing \`.claude/\` collision map (reconcile $ts)"
    echo "- Backup of your original \`.claude/\`: \`$BK\` (fully reversible)."
    echo "- **Preserved, never overwritten:** \`settings.local.json\`, \`.claude/state/\`, \`.claude/memory/\`, existing \`.claude/rules/*\`, \`conventions.yml\`, your secrets."
    echo "- **Factory now governs (overwritten, backed up):** agents, skills, commands, hooks, scripts, routines, statuslines, output-styles, CLAUDE.md, settings.json."
    [ -n "$conflict_claude" ] && {
      echo "- Your original CLAUDE.md → \`.claude/CLAUDE.md.brownfield-orig\`. The factory CLAUDE.md (8-phase workflow, commit protocol, gates) governs process; **migrate your project conventions into \`AGENTS.md\`**."
      echo "- [OQ] Reconcile CLAUDE.md: review \`.brownfield-orig\` vs factory; decide per axis (factory wins on process; your conventions → AGENTS.md). Resolve via /clarify."
    }
    [ -n "$conflict_settings" ] && echo "- [OQ] Your settings.json → \`.brownfield-orig\`. Move any custom \`allow\`/\`deny\` permissions into \`.claude/settings.local.json\` (never committed)."
  } >> "$REPORT"
fi

echo "✓ reconciled. Review the collision map in $REPORT, resolve [OQ]s via /clarify, then: bash .claude/scripts/setup.sh"
