#!/usr/bin/env bash
# Validate a NEXUS handoff YAML against the schema. Round 6 D.
#
# Usage:
#   bash .claude/scripts/validate-handoff.sh <file.yaml>
#   bash .claude/scripts/validate-handoff.sh --stdin   # read from stdin
#
# Exit codes:
#   0 — valid
#   2 — invalid (missing required field, wrong type, etc.) — used by hook block
#   3 — couldn't parse YAML at all
#
# Uses yq if available; falls back to grep-based shape check that catches
# missing required keys but doesn't validate enum values.

set -uo pipefail

SOURCE="${1:-}"
if [ "$SOURCE" = "--stdin" ]; then
  tmp=$(mktemp)
  cat > "$tmp"
  SOURCE="$tmp"
  cleanup() { rm -f "$tmp"; }
  trap cleanup EXIT
fi

if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
  echo "validate-handoff: file required" >&2
  exit 1
fi

# ─── Required fields ────────────────────────────────────────────────────
required_fields=(
  schema_version
  subagent_name
  status
  summary
  artifacts_created
  files_modified
  decisions_made
  blockers_encountered
  tokens_used
  turns_used
)

# ─── Enum-validated fields ──────────────────────────────────────────────
valid_statuses="completed qa_pass qa_fail escalated blocked aborted"
valid_confidences="high medium low"

issues=0

# Try yq for proper parse
if command -v yq >/dev/null 2>&1; then
  for field in "${required_fields[@]}"; do
    val=$(yq eval ".$field // null" "$SOURCE" 2>/dev/null)
    if [ "$val" = "null" ] || [ -z "$val" ]; then
      echo "✗ missing required field: $field"
      issues=$((issues + 1))
    fi
  done

  status=$(yq eval '.status // ""' "$SOURCE" 2>/dev/null)
  if [ -n "$status" ] && ! echo "$valid_statuses" | grep -qw "$status"; then
    echo "✗ invalid status: '$status' (must be: $valid_statuses)"
    issues=$((issues + 1))
  fi

  confidence=$(yq eval '.confidence // ""' "$SOURCE" 2>/dev/null)
  if [ -n "$confidence" ] && ! echo "$valid_confidences" | grep -qw "$confidence"; then
    echo "✗ invalid confidence: '$confidence' (must be: $valid_confidences)"
    issues=$((issues + 1))
  fi

  # If status=qa_pass, evidence_paths must be populated
  if [ "$status" = "qa_pass" ]; then
    paths_count=$(yq eval '.evidence_paths | length' "$SOURCE" 2>/dev/null)
    if [ "${paths_count:-0}" -eq 0 ]; then
      echo "✗ status=qa_pass requires evidence_paths to be populated"
      issues=$((issues + 1))
    fi
  fi
else
  # Fallback: grep-based shape check
  for field in "${required_fields[@]}"; do
    if ! grep -qE "^${field}:" "$SOURCE"; then
      echo "✗ missing required field: $field"
      issues=$((issues + 1))
    fi
  done
  # Strip inline `# comment` before extracting value
  status=$(grep -E '^status:' "$SOURCE" | head -1 | sed 's/status:[[:space:]]*//' | sed 's/[[:space:]]*#.*$//' | tr -d '"' | tr -d ' ')
  if [ -n "$status" ] && ! echo "$valid_statuses" | grep -qw "$status"; then
    echo "✗ invalid status: '$status' (must be: $valid_statuses)"
    issues=$((issues + 1))
  fi
fi

if [ "$issues" -eq 0 ]; then
  echo "✓ handoff valid"
  exit 0
else
  echo
  echo "✗ $issues issues — see .swarms/templates/handoff.yaml for the schema"
  exit 2
fi
