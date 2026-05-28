#!/usr/bin/env bash
# PostToolUse hook. Appends a compact observation to instincts/observations.jsonl
# for the instinct skill's Haiku extractor to consume.
# PII-clean: relative paths, no Bash stdout content, only exit codes + error class.

set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

mkdir -p .claude/memory/.cache/instincts
log=".claude/memory/.cache/instincts/observations.jsonl"

ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' | head -c 200)
    exit_code=$(printf '%s' "$input" | jq -r '.tool_response.exit_code // .tool_response.exitCode // 0')

    # Extract just the command name (first word) to keep it PII-light
    cmd_name=$(echo "$cmd" | awk '{print $1}')

    # Error class (rough heuristic, not the actual error text)
    err_class=""
    if [ "$exit_code" != "0" ]; then
      err_stderr=$(printf '%s' "$input" | jq -r '.tool_response.stderr // ""' | head -c 200)
      case "$err_stderr" in
        *"ENOENT"*|*"not found"*) err_class="missing" ;;
        *"timeout"*|*"timed out"*) err_class="timeout" ;;
        *"permission"*|*"EACCES"*) err_class="permission" ;;
        *"already exists"*) err_class="conflict" ;;
        *"syntax"*) err_class="syntax" ;;
        *) err_class="other" ;;
      esac
    fi

    jq -nc \
      --arg ts "$ts" \
      --arg tool "Bash" \
      --arg cmd "$cmd_name" \
      --argjson exit "$exit_code" \
      --arg err "$err_class" \
      '{ts:$ts,tool:$tool,cmd:$cmd,exit:$exit,err:$err}' >> "$log"
    ;;
  Write|Edit)
    file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""')
    # Make path relative to project root
    rel_path="${file#"$(pwd)/"}"
    jq -nc \
      --arg ts "$ts" \
      --arg tool "$tool" \
      --arg file "$rel_path" \
      '{ts:$ts,tool:$tool,file:$file}' >> "$log"
    ;;
esac

# Rotate if log exceeds 1 MB (keep last 5000 lines)
if [ -f "$log" ]; then
  size=$(wc -c < "$log" | tr -d ' ')
  if [ "$size" -gt 1000000 ]; then
    tail -5000 "$log" > "$log.tmp" && mv "$log.tmp" "$log"
  fi
fi

exit 0
