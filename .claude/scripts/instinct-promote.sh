#!/usr/bin/env bash
# Project → global instinct promotion — gap-audit G26 (was purely aspirational).
#
# Global store: ~/.claude/memory/instincts/global.yml. Each promoted entry
# carries provenance (projects: [<path>, ...]). The documented 2-project
# threshold is enforced via that provenance list: `auto` only marks an entry
# status: global once a SECOND distinct project promotes/observes the same
# trigger; a single-project entry sits in global.yml as status: candidate.
#
# Usage:
#   bash instinct-promote.sh auto            # promote all confidence ≥0.8 entries
#   bash instinct-promote.sh promote <id>    # manually promote one entry
#   bash instinct-promote.sh list            # show global store
#
# Invoked from the dream skill (step 4b) and /instinct promote.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ACTIVE=".claude/memory/instincts/active.yml"
GLOBAL_DIR="${INSTINCT_GLOBAL_DIR:-$HOME/.claude/memory/instincts}"
GLOBAL="$GLOBAL_DIR/global.yml"
PROJECT="$ROOT"

mode="${1:-auto}"
want_id="${2:-}"

[ "$mode" = "list" ] && { cat "$GLOBAL" 2>/dev/null || echo "(no global instincts yet)"; exit 0; }
[ -s "$ACTIVE" ] || exit 0
mkdir -p "$GLOBAL_DIR"
touch "$GLOBAL"

# Walk active.yml entry blocks (- id: ... until next "- id:").
# For each candidate: if its trigger already exists in global.yml under a
# DIFFERENT project → 2-project threshold met → status: global.
promoted=0
current_block=""
flush_block() {
  [ -z "$current_block" ] && return 0
  id=$(printf '%s\n' "$current_block" | grep -E '^- id:' | head -1 | sed 's/- id:[[:space:]]*//' | tr -d '"')
  trigger=$(printf '%s\n' "$current_block" | grep -E '^[[:space:]]*trigger:' | head -1 | sed 's/.*trigger:[[:space:]]*//' | tr -d '"')
  conf=$(printf '%s\n' "$current_block" | grep -E '^[[:space:]]*confidence:' | head -1 | grep -oE '[0-9.]+' || echo 0)
  [ -z "$id" ] || [ -z "$trigger" ] && return 0

  if [ "$mode" = "promote" ]; then
    [ "$id" = "$want_id" ] || return 0
  else
    # auto mode: confidence gate ≥ 0.8
    awk -v c="$conf" 'BEGIN { exit !(c >= 0.8) }' || return 0
  fi

  esc_trigger=$(printf '%s' "$trigger" | sed 's/[][\.*^$/]/\\&/g')
  if grep -qE "^[[:space:]]*trigger:[[:space:]]*\"?${esc_trigger}" "$GLOBAL" 2>/dev/null; then
    # Trigger already global — add this project to provenance if new, and
    # flip candidate → global when a 2nd distinct project appears.
    if ! awk -v trg="$trigger" -v proj="$PROJECT" '
        $0 ~ "trigger:" && index($0, trg) { inb=1 }
        inb && $0 ~ "projects:" && index($0, proj) { found=1 }
        /^- id:/ { inb=0 }
        END { exit found ? 0 : 1 }' "$GLOBAL"; then
      tmp=$(mktemp)
      awk -v trg="$trigger" -v proj="$PROJECT" '
        { print }
        $0 ~ "trigger:" && index($0, trg) { mark=1 }
        mark && /projects:/ { print "    - " proj; mark=0 }
      ' "$GLOBAL" > "$tmp" && mv "$tmp" "$GLOBAL"
      # 2nd project just landed → threshold met
      tmp=$(mktemp)
      awk -v trg="$trigger" '
        $0 ~ "trigger:" && index($0, trg) { inb=1 }
        inb && /status: candidate/ { sub(/status: candidate/, "status: global") ; inb=0 }
        { print }
      ' "$GLOBAL" > "$tmp" && mv "$tmp" "$GLOBAL"
      promoted=$((promoted + 1))
      echo "↑ cross-project threshold met: $id (now status: global)"
    fi
  else
    {
      printf '%s\n' "$current_block" | sed 's/status: project/status: candidate/'
      echo "  projects:"
      echo "    - $PROJECT"
    } >> "$GLOBAL"
    promoted=$((promoted + 1))
    echo "→ staged in global store as candidate (needs a 2nd project): $id"
  fi
}

while IFS= read -r line; do
  case "$line" in
    "- id:"*)
      flush_block
      current_block="$line"
      ;;
    *)
      [ -n "$current_block" ] && current_block="$current_block
$line"
      ;;
  esac
done < "$ACTIVE"
flush_block

echo "Done: $promoted entries processed into $GLOBAL"
exit 0
