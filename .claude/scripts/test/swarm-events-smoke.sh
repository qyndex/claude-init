#!/usr/bin/env bash
# Swarm-events end-to-end smoke test (Spec 001 AC-17).
#
# Tagged: AC-17
#
# Spawns a single MOCK stream: appends a well-formed lane.started then
# lane.finished JSONL record to a SANDBOX events dir (mktemp, trap-cleaned —
# never the real .swarms/events/), then asserts:
#   (a) the file is well-formed JSONL — every line is valid JSON (jq -e .),
#   (b) it contains >=1 lane.started and >=1 lane.finished,
#   (c) each event carries the schema's required keys (ts, stream_id, event,
#       payload) and a schema-enumerated event value.
#
# Portable for BSD + GNU (macOS default shell). No nested process substitution.
#
# lint-silent-failures: ignore-file
# This is a TEST: its jq calls deliberately mute stderr because the assertion's
# exit code (captured via `check`) is the signal, not jq's diagnostic noise. The
# silent-failure gate targets production scripts where a swallowed error hides a
# real fault; in a test the swallowed error simply fails the assertion below.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCHEMA="$ROOT/.swarms/templates/lane-event-schema.json"

pass=0
fail=0
fails=()

check() {
  # check <label> <condition-exit-code>
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then
    pass=$((pass+1))
  else
    fail=$((fail+1))
    fails+=("$label")
  fi
}

# Required keys + enum, read straight from the canonical schema so the mock
# stays honest if the schema ever changes shape.
REQUIRED_KEYS="$(jq -r '.required[]' "$SCHEMA" 2>/dev/null | sort | tr '\n' ' ')"
ENUM_VALUES="$(jq -r '.properties.event.enum[]' "$SCHEMA" 2>/dev/null)"

# Sandbox events dir — never pollute the real .swarms/events/.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EVENTS_DIR="$TMP/events"
mkdir -p "$EVENTS_DIR"

STREAM_ID="feat-smoke-$$"
EVENTS_FILE="$EVENTS_DIR/$STREAM_ID.jsonl"

# --- mock stream: emit a lane.started then a lane.finished JSONL line ---
emit() { # emit <event> <payload-json>
  local event="$1" payload="$2"
  jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "$STREAM_ID" \
    --arg ev "$event" \
    --argjson pl "$payload" \
    '{ts: $ts, stream_id: $sid, event: $ev, payload: $pl}' \
    >>"$EVENTS_FILE"
}

emit "lane.started"  '{"task":"T-038"}'
emit "lane.finished" '{"task":"T-038","exit_code":0}'

# --- (0) file exists and is non-empty ---
[ -s "$EVENTS_FILE" ]
check "events-file-created: .swarms/events/<stream-id>.jsonl exists and is non-empty" $?

# --- (a) every line is well-formed JSON ---
jsonl_ok=0
line_count=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  line_count=$((line_count+1))
  if ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
    jsonl_ok=1
  fi
done <"$EVENTS_FILE"
[ "$jsonl_ok" -eq 0 ] && [ "$line_count" -ge 2 ]
check "well-formed-jsonl: each of $line_count lines is valid JSON" $?

# --- (b) contains >=1 lane.started and >=1 lane.finished ---
started_n="$(jq -r 'select(.event=="lane.started") | .event' "$EVENTS_FILE" 2>/dev/null | grep -c 'lane.started')"
finished_n="$(jq -r 'select(.event=="lane.finished") | .event' "$EVENTS_FILE" 2>/dev/null | grep -c 'lane.finished')"
[ "${started_n:-0}" -ge 1 ]
check "has-lane-started: at least one lane.started event present" $?
[ "${finished_n:-0}" -ge 1 ]
check "has-lane-finished: at least one lane.finished event present" $?

# --- (c) every event carries the schema's required keys + enum-valid event ---
keys_ok=0
enum_ok=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  got_keys="$(printf '%s\n' "$line" | jq -r 'keys[]' 2>/dev/null | sort | tr '\n' ' ')"
  if [ "$got_keys" != "$REQUIRED_KEYS" ]; then
    keys_ok=1
  fi
  ev="$(printf '%s\n' "$line" | jq -r '.event' 2>/dev/null)"
  if ! printf '%s\n' "$ENUM_VALUES" | grep -qx "$ev"; then
    enum_ok=1
  fi
done <"$EVENTS_FILE"
[ "$keys_ok" -eq 0 ]
check "schema-required-keys: every event has exactly [$REQUIRED_KEYS]" $?
[ "$enum_ok" -eq 0 ]
check "schema-enum-event: every event value is schema-enumerated" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
exit 0
