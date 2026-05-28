#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks destructive commands.
# Reads tool input from stdin (JSON), emits JSON decision to stdout.
# Exit code 0 = continue with normal permission flow; exit 2 = block.

set -euo pipefail

# Read stdin
input=$(cat)

# Extract the command
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

if [ -z "$cmd" ]; then
  exit 0
fi

# Normalize: collapse multiple whitespace to single spaces for regex matching.
# This catches the "rm  -rf  /" double-space evasion.
cmd_normalized=$(echo "$cmd" | tr -s '[:space:]' ' ')

# Destructive patterns. If matched, deny with a clear reason.
# Patterns match against the normalized command. Chained commands (;, &&, ||, |)
# are split below and EACH segment is checked independently.
deny_patterns=(
  # rm dangerous targets
  'rm +-rf +/'
  'rm +-rf +~'
  'rm +-rf +\$HOME'
  # Fork bomb
  ':\(\) *\{ *:\|:& *\} *;:'
  # Disk-destroying
  'dd +if='
  'mkfs\.'
  'sudo +rm'
  # Pipe-to-shell from network
  'curl .*\| *sh'
  'curl .*\| *bash'
  'wget .*\| *sh'
  'wget .*\| *bash'
  'curl .*\| *zsh'
  'wget .*\| *zsh'
  # Indirect execution paths
  'base64 +(-d|--decode) +.* *\| *(sh|bash|zsh)'
  'echo +.* *\| *base64 +-d *\| *(sh|bash|zsh)'
  'python3? +-c +'
  'perl +-e +'
  'node +-e +'
  'ruby +-e +'
  'bash +<\('
  'sh +<\('
  'eval +'
  'exec +'
  'source +/dev/stdin'
  # Git force-push to main/master
  'git +push +(--force|--force-with-lease *|-f) +origin +(main|master|HEAD:main|HEAD:master)'
  'git +(commit|push) +.*--no-verify'
  'git +reset +--hard +origin/(main|master)'
  'git +branch +-D +(main|master)'
  'git +clean +-fdx'
  # SQL destruction
  'DROP +DATABASE'
  'DROP +TABLE'
  'TRUNCATE +TABLE'
  'DELETE +FROM +[^ ]+ +WHERE +1 *= *1'
  # Permission/ownership broadening
  'chmod +(-R +)?777'
  'chmod +(-R +)?a\+w +(/|~|\$HOME)'
  'chown +-R +.* +(/|~|\$HOME)'
)

# Split the command on chaining delimiters (;, &&, ||, |) so each segment is
# checked independently. This catches `git status; rm -rf ~/proj` even though
# the chained whole doesn't start with `rm`.
# IFS-based split keeps the implementation in pure bash, no external tools.
IFS=$'\n' read -r -d '' -a segments < <(printf '%s' "$cmd_normalized" | sed -E 's/[;|&]+/\n/g' ; printf '\0')

check_segment() {
  local seg="$1"
  for pattern in "${deny_patterns[@]}"; do
    if [[ "$seg" =~ $pattern ]]; then
      cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by .claude/hooks/pre-bash-guard.sh: segment '$seg' matches destructive pattern /$pattern/. If you intended this, run it interactively in a shell, not through the agent."
  }
}
EOF
      exit 0
    fi
  done
}

# Check each segment AND the original normalized command (catches patterns that span splits).
for seg in "${segments[@]}"; do
  check_segment "$seg"
done
check_segment "$cmd_normalized"

# Patterns that should always ask (even if not in settings.ask)
ask_patterns=(
  '^rm[[:space:]]+-rf[[:space:]]'
  'git[[:space:]]+push.*--force'
  'git[[:space:]]+push.*-f[[:space:]]'
  'docker[[:space:]]+system[[:space:]]+prune'
)

for pattern in "${ask_patterns[@]}"; do
  if [[ "$cmd" =~ $pattern ]]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Sensitive command — confirm intent. Pattern: '$pattern'"
  }
}
EOF
    exit 0
  fi
done

exit 0
