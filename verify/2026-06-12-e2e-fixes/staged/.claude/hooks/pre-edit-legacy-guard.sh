#!/usr/bin/env bash
# PreToolUse hook for Write|Edit|NotebookEdit — "no tests = no writes", enforced
# at WRITE TIME (e2e-audit brownfield-2).
#
# verify.sh's characterization gate fires at verify time — AFTER the damage to
# un-characterized legacy code is already on disk (and possibly committed by an
# auto-mode loop that never runs verify). This hook makes the brownfield safety
# promise deterministic: an edit to a path flagged in
# .claude/state/adopt/uncharacterized-paths.txt is denied (exit 2) unless a
# matching characterization test already exists. The unblock path is the
# `characterize` skill (write the golden-master test first), not an env var.
#
# Operator escape: SKIP_CHAR_GATE=1 honored ONLY with the human-created
# .claude/state/allow-skip-gates marker — same contract as verify.sh.
# Latency budget: <50ms when no manifest exists (the common case).

set -uo pipefail

MANIFEST=".claude/state/adopt/uncharacterized-paths.txt"
[ -s "$MANIFEST" ] || exit 0

# Operator escape (mirrors verify.sh's allow-skip-gates contract).
if [ "${SKIP_CHAR_GATE:-0}" = "1" ] && [ -f .claude/state/allow-skip-gates ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "pre-edit-legacy-guard: jq missing — failing CLOSED for legacy-path writes. Install jq." >&2
  exit 2
fi

# JUSTIFIED: || true tolerates closed stdin; empty payload has nothing to guard
payload=$(cat 2>/dev/null || true)
[ -z "$payload" ] && exit 0

file_path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
[ -z "$file_path" ] && exit 0

# Repo-relative normalization (same approach as pre-edit-constitution-guard.sh).
# JUSTIFIED: cd error discarded — unreachable dir leaves ROOT empty and rel stays raw, still matched below
ROOT="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd || echo "")"
rel="$file_path"
if [ -n "$ROOT" ]; then
  case "$file_path" in "$ROOT"/*) rel="${file_path#$ROOT/}" ;; esac
fi
while [ "$rel" != "${rel#./}" ]; do rel="${rel#./}"; done

# Tests/specs/characterization files never need their own characterization test
# (identical carve-out to verify.sh's gate).
case "$rel" in
  *test*|*spec*|*Test*|*Spec*|*characterization*) exit 0 ;;
esac

while IFS= read -r glob; do
  case "$glob" in ''|\#*) continue ;; esac
  # shellcheck disable=SC2254
  case "$rel" in
    $glob)
      base=$(basename "$rel"); base="${base%.*}"
      # JUSTIFIED: find noise muted — grep -q decides presence; "no match" is the deny trigger
      if ! find . -type d -name node_modules -prune -o -type f \
           \( -iname "*${base}*characterization*" -o -iname "*characterization*${base}*" \) -print 2>/dev/null | grep -q .; then
        reason="Legacy path '${rel}' is flagged in ${MANIFEST} and has NO characterization test — write a golden-master test first (skill: characterize), then retry. 'No tests = no writes' (e2e-audit brownfield-2)."
        jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
        echo "$reason" >&2
        exit 2
      fi
      ;;
  esac
done < "$MANIFEST"

exit 0
