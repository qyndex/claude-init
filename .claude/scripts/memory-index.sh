#!/usr/bin/env bash
# Memory v2 index — typed manifest at .claude/memory/index.jsonl
#
# Round 5 Batch C1: replaces grep-on-paths retrieval with a queryable index.
# Every memory artifact (ADR, pattern, incident, playbook, deprecation) gets
# one line in index.jsonl with structured fields.
#
# Operations:
#   bash .claude/scripts/memory-index.sh backfill   # one-time: scan existing files, build initial index
#   bash .claude/scripts/memory-index.sh touch <file>   # called by post-write-format hook on memory writes
#   bash .claude/scripts/memory-index.sh query --type incident --tag auth   # query
#   bash .claude/scripts/memory-index.sh query --paths-touched 'src/auth/*'
#   bash .claude/scripts/memory-index.sh verify    # check internal consistency (ref/back_ref symmetry)
#   bash .claude/scripts/memory-index.sh rebuild   # blow away + rebuild from disk

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# M-10-lock: all memory-plane writers share ONE lock so a backgrounded dream's
# rebuild can't interleave with a live PostToolUse `touch` (post-write-format.sh)
# and silently drop the just-written entry. mkdir-atomic, ships everywhere.
# shellcheck source=lib/with-lock.sh
. "$(dirname "$0")/lib/with-lock.sh"

INDEX=".claude/memory/index.jsonl"
mkdir -p .claude/memory

extract_field() {
  # Pulls one field from YAML frontmatter or markdown body. Returns "" if missing.
  local file="$1" field="$2"
  awk -v field="$field" '
    /^---$/ { fm = !fm; next }
    fm && $0 ~ "^" field ":" {
      sub("^" field ":[[:space:]]*", "")
      gsub(/"/, "")
      print
      exit
    }
  ' "$file"
}

extract_paths_touched() {
  # Grep paths mentioned in the body (lines with file:// or src/ or src/**/ patterns)
  local file="$1"
  # JUSTIFIED: a memory file with no code-path mentions makes grep exit 1 — the pipeline then produces an empty JSON array via jq, the correct "no paths_touched" value
  grep -oE '`[a-zA-Z0-9_./-]+\.(ts|tsx|js|jsx|py|go|rs|java|kt|sql|md|yml|yaml|json|sh|css|html|toml)`' "$file" 2>/dev/null \
    | sed 's/`//g' \
    | sort -u \
    | head -20 \
    | jq -R . | jq -sc .
}

extract_refs() {
  # Find references to other memory items (ADR-XXXX, [[name]] wikilinks)
  local file="$1"
  {
    # JUSTIFIED: a file with no ADR-refs / wikilinks makes both greps exit 1 — the group then yields an empty refs array via jq, the correct "no references" value
    grep -oE 'ADR-[0-9]+' "$file" 2>/dev/null
    grep -oE '\[\[[a-z0-9-]+\]\]' "$file" 2>/dev/null | sed 's/\[\[//;s/\]\]//'
  } | sort -u | jq -R . | jq -sc .
}

determine_type() {
  local file="$1"
  case "$file" in
    .claude/memory/decisions/*) echo decision ;;
    .claude/memory/patterns/*) echo pattern ;;
    .claude/memory/incidents/*) echo incident ;;
    .claude/memory/playbooks/*) echo playbook ;;
    .claude/memory/deprecations/*) echo deprecation ;;
    .claude/memory/audits/*) echo audit ;;
    .claude/memory/rollups/*) echo rollup ;;
    *) echo other ;;
  esac
}

build_entry() {
  local file="$1"
  [ -f "$file" ] || return 1

  local type=$(determine_type "$file")
  local id=$(basename "$file" .md)
  local status=$(extract_field "$file" "status")
  local created=$(extract_field "$file" "created")
  [ -z "$created" ] && created=$(extract_field "$file" "Date")
  # seed-patterns frontmatter uses written_at — without this fallback every
  # seeded file indexed with created:"" and the promotion lifecycle never fired
  [ -z "$created" ] && created=$(extract_field "$file" "written_at")
  local last_verified=$(extract_field "$file" "last_verified")
  local written_by=$(extract_field "$file" "written_by")
  local source_session=$(extract_field "$file" "source_session")
  local superseded_by=$(extract_field "$file" "superseded_by")
  local owners=$(extract_field "$file" "Owners")
  [ -z "$owners" ] && owners=$(extract_field "$file" "owner")
  local recurred_at=$(extract_field "$file" "recurred_at")
  local paths_touched=$(extract_paths_touched "$file")
  local refs=$(extract_refs "$file")
  # JUSTIFIED: GNU-vs-BSD stat probe — whichever flag form the platform rejects is muted; the surviving form supplies mtime, and a vanished file leaves it empty (indexed as 0 downstream)
  local mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)

  jq -nc \
    --arg path "$file" \
    --arg id "$id" \
    --arg type "$type" \
    --arg status "${status:-unknown}" \
    --arg created "${created:-}" \
    --arg last_verified "${last_verified:-}" \
    --arg written_by "${written_by:-unknown}" \
    --arg source_session "${source_session:-}" \
    --arg superseded_by "${superseded_by:-}" \
    --arg owners "${owners:-}" \
    --arg recurred_at "${recurred_at:-}" \
    --argjson paths_touched "${paths_touched:-[]}" \
    --argjson refs "${refs:-[]}" \
    --arg mtime "${mtime:-0}" \
    '{
      path: $path,
      id: $id,
      type: $type,
      status: $status,
      created: $created,
      last_verified: $last_verified,
      written_by: $written_by,
      source_session: $source_session,
      superseded_by: $superseded_by,
      owners: ($owners | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))),
      recurred_at: $recurred_at,
      paths_touched: $paths_touched,
      refs: $refs,
      back_refs: [],
      mtime: ($mtime | tonumber)
    }'
}

cmd="${1:-help}"
# JUSTIFIED: when invoked with no args the shift has nothing to drop and exits non-zero — harmless, the fallback keeps the script going to the help case
shift || true

# M-10-lock: the two write paths are functions so with_lock can wrap them.
_rebuild_index() {
    echo "→ Building memory index..."
    > "$INDEX"
    count=0
    while IFS= read -r -d '' f; do
      entry=$(build_entry "$f")
      if [ -n "$entry" ]; then
        echo "$entry" >> "$INDEX"
        count=$((count + 1))
      fi
    done < <(find .claude/memory \
      -name '*.md' \
      -not -name '0000-template.md' \
      -not -name 'in-flight*.md' \
      -not -path '*/.cache/*' \
      -not -path '*/audits/*' \
      -type f -print0 2>/dev/null) # JUSTIFIED: mutes find traversal warnings on a sparse memory tree; an empty set just means zero artifacts to index

    # Now walk forward refs to populate back_refs (second pass)
    if [ "$count" -gt 0 ]; then
      tmp=$(mktemp)
      # JUSTIFIED: muting parse noise here is safe — a freshly written index with no refs yields an empty refs file and the back_ref pass simply does nothing
      jq -c '. as $entry | .refs[] | select(. != null) | {target: ., source: $entry.id}' "$INDEX" 2>/dev/null > "$tmp.refs"

      while IFS= read -r line; do
        target=$(echo "$line" | jq -r .target)
        source=$(echo "$line" | jq -r .source)
        # Find target in index, append source to back_refs
        jq -c --arg t "$target" --arg s "$source" '
          if .id == $t or (.id | endswith($t)) then
            .back_refs += [$s] | .back_refs |= unique
          else . end
        ' "$INDEX" > "$tmp"
        mv "$tmp" "$INDEX"
      done < "$tmp.refs"
      rm -f "$tmp.refs"
    fi

    echo "✓ Indexed $count memory artifacts → $INDEX"
}

# M-11: set-or-replace ONE frontmatter key, operating strictly inside the leading
# `---` fence (never the body — avoids the sed-on-body class of bug M-03 fixed).
# If the key exists it is replaced in place; otherwise it is appended just before
# the closing fence. Idempotent.
_fm_set() {
  local file="$1" key="$2" val="$3" tmp
  tmp=$(mktemp)
  awk -v key="$key" -v val="$val" '
    BEGIN { fm=0; done=0 }
    /^---$/ {
      if (fm==0) { fm=1; print; next }
      # closing fence: append the key here if we never saw it
      if (fm==1 && !done) { print key ": " val; done=1 }
      fm=2; print; next
    }
    fm==1 && $0 ~ ("^" key ":") {
      if (!done) { print key ": " val; done=1 }
      next   # drop any duplicate/old line for this key
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

_adr_path() { # <id-or-stem> → decisions file path, or empty
  local id="$1" f
  f=".claude/memory/decisions/${id}.md"
  [ -f "$f" ] && { echo "$f"; return 0; }
  # allow bare numeric / ADR-NNNN forms → match by prefix
  id="${id#ADR-}"
  for f in .claude/memory/decisions/${id}*.md; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

_supersede() {
  local old_id="$1" new_id="$2" old_f new_f old_num new_num
  old_f=$(_adr_path "$old_id") || { echo "supersede: old ADR not found: $old_id" >&2; return 1; }
  new_f=$(_adr_path "$new_id") || { echo "supersede: new ADR not found: $new_id" >&2; return 1; }
  # Canonical ADR-NNNN tokens from the filename stems.
  old_num="ADR-$(basename "$old_f" .md | grep -oE '^[0-9]+')"
  new_num="ADR-$(basename "$new_f" .md | grep -oE '^[0-9]+')"

  _fm_set "$old_f" "status" "superseded"
  _fm_set "$old_f" "superseded_by" "$new_num"
  _fm_set "$new_f" "supersedes" "$old_num"

  # Rebuild so the index (and recall's -5 penalty) reflects the new frontmatter.
  _rebuild_index >/dev/null
  echo "✓ $new_num supersedes $old_num"
}

_touch_index() {
    local file="$1"
    entry=$(build_entry "$file") || return 0
    [ -z "$entry" ] && return 0

    id=$(echo "$entry" | jq -r .id)
    # Remove old entry, append new
    tmp=$(mktemp)
    # JUSTIFIED: filters the prior entry for this id out of the index; a missing or single-line index makes grep find nothing and exit non-zero, so the fallback keeps the temp file empty and the fresh entry is appended below
    grep -v "\"id\":\"$id\"" "$INDEX" 2>/dev/null > "$tmp" || true
    echo "$entry" >> "$tmp"
    mv "$tmp" "$INDEX"
}

case "$cmd" in
  backfill|rebuild)
    # M-10-lock: serialize the truncate-then-rewrite against any concurrent touch.
    with_lock "memory-plane" _rebuild_index
    ;;

  touch)
    file="${1:-}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
      echo "memory-index: touch <file> — file required and must exist" >&2
      exit 1
    fi
    case "$file" in
      .claude/memory/*) ;;
      *) exit 0 ;;  # Not a memory file; nothing to index
    esac
    # M-10-lock: serialize the read-modify-write against a concurrent rebuild.
    with_lock "memory-plane" _touch_index "$file"
    ;;

  query)
    if [ ! -f "$INDEX" ]; then
      echo "Index missing — run: bash .claude/scripts/memory-index.sh backfill" >&2
      exit 1
    fi

    filter='.'
    while [ $# -gt 0 ]; do
      case "$1" in
        --type) filter="$filter | select(.type == \"$2\")"; shift 2 ;;
        --status) filter="$filter | select(.status == \"$2\")"; shift 2 ;;
        --owner) filter="$filter | select(.owners | any(. == \"$2\"))"; shift 2 ;;
        --path-prefix) filter="$filter | select(.paths_touched | any(startswith(\"$2\")))"; shift 2 ;;
        --tag) filter="$filter | select(.path | contains(\"$2\") or (.refs // [] | any(. | contains(\"$2\"))))"; shift 2 ;;
        --since) filter="$filter | select(.created >= \"$2\")"; shift 2 ;;
        --recurred) filter="$filter | select(.recurred_at != \"\" and .recurred_at != null)"; shift 1 ;;
        *) echo "Unknown filter: $1" >&2; exit 1 ;;
      esac
    done

    # JUSTIFIED: a query against an index with no matching entries should print nothing rather than emit jq filter noise to the user
    jq -c "$filter" "$INDEX" 2>/dev/null
    ;;

  verify)
    if [ ! -f "$INDEX" ]; then
      echo "Index missing — run backfill first" >&2; exit 1
    fi
    # Check ref ↔ back_ref symmetry
    issues=0
    while IFS= read -r entry; do
      id=$(echo "$entry" | jq -r .id)
      for ref in $(echo "$entry" | jq -r '.refs[]'); do
        # JUSTIFIED: a ref pointing at an absent target yields no back_refs and exit non-zero — empty is the intended value, the symmetry check below then reports the asymmetry
        target_back_refs=$(jq -r --arg t "$ref" 'select(.id == $t or (.id | endswith($t))) | .back_refs[]' "$INDEX" 2>/dev/null)
        if ! echo "$target_back_refs" | grep -q "^${id}$"; then
          echo "⚠ $id → $ref but $ref does not back-ref $id"
          issues=$((issues + 1))
        fi
      done
    done < "$INDEX"
    echo "verify: $issues asymmetries"
    [ "$issues" -eq 0 ]
    ;;

  supersede)
    # M-11: <old-id> <new-id> — flip old ADR frontmatter (status + superseded_by),
    # stamp the new ADR (supersedes), rebuild. Locked (mutates + rebuilds index).
    old_id="${1:-}"; new_id="${2:-}"
    if [ -z "$old_id" ] || [ -z "$new_id" ]; then
      echo "memory-index: supersede <old-adr-id> <new-adr-id>" >&2; exit 1
    fi
    with_lock "memory-plane" _supersede "$old_id" "$new_id"
    ;;

  *)
    cat <<EOF
memory-index.sh — typed memory manifest

Usage:
  $0 backfill                 # one-time: build initial index from existing files
  $0 rebuild                  # blow away + rebuild
  $0 touch <path>             # update index entry for one file (called from hook)
  $0 supersede <old> <new>    # M-11: flip old ADR frontmatter + rebuild (recall -5)
  $0 query [filters]          # query the index
                              # filters: --type X --status Y --owner @u
                              #          --path-prefix src/ --tag auth
                              #          --since YYYY-MM-DD --recurred
  $0 verify                   # check ref/back_ref symmetry
EOF
    ;;
esac
