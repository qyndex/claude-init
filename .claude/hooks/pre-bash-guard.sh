#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks destructive commands.
# Reads tool input from stdin (JSON), emits JSON decision to stdout.
# Exit code 0 = continue with normal permission flow; exit 2 = block.
#
# e2e-audit hooks-engineering-1/-2/-4, security-automode-2/-4 rescope:
#   - quoted-string spans are stripped before segment-splitting, so commit
#     messages and other quoted CONTENT no longer trip command patterns
#   - exec/eval/interpreter -c|-e are anchored to command position (start of a
#     segment, after optional env assignments) — `kubectl exec`, `pnpm exec`,
#     "exec bits" in prose no longer match
#   - `rm -rf /` is scoped to dangerous roots (/, /etc, /usr, ~, $HOME, ...)
#     instead of any absolute path
#   - any-content-piped-into-shell and $VAR-indirection of rm/curl are ASK
#   - jq is mandatory (fail closed): malformed input denies, never crashes

set -uo pipefail

# Fail-closed jq preamble (hooks-engineering-4): this guard is the first line of
# defense — without jq it cannot parse the payload, so it must deny, not pass.
if ! command -v jq >/dev/null 2>&1; then
  echo "Blocked by .claude/hooks/pre-bash-guard.sh: jq is not installed; the guard cannot parse tool input and fails CLOSED. Install jq (brew install jq) to run Bash commands." >&2
  exit 2
fi

# Read stdin
# JUSTIFIED: || true tolerates a closed stdin; the -z guard below handles it
input=$(cat 2>/dev/null || true)
[ -z "$input" ] && exit 0

# Extract the command. Malformed non-empty JSON → deny (fail closed), never abort.
if ! cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null); then
  echo "Blocked by .claude/hooks/pre-bash-guard.sh: tool input is not parseable JSON; failing closed." >&2
  exit 2
fi

if [ -z "$cmd" ]; then
  exit 0
fi

# Normalize: collapse multiple whitespace to single spaces for regex matching.
# This catches the "rm  -rf  /" double-space evasion.
cmd_normalized=$(echo "$cmd" | tr -s '[:space:]' ' ')

# Strip quoted-string spans (hooks-engineering-1): quoted text is CONTENT
# (commit messages, grep patterns, awk programs), not commands. Replace each
# span with <q> so segment-splitting cannot split inside quotes and command
# patterns cannot match prose. Escaped quotes inside double quotes are dropped
# first so the span regex terminates at the real closing quote.
cmd_stripped=$(printf '%s' "$cmd_normalized" | sed -E "s/\\\\[\"']//g; s/'[^']*'/<q>/g; s/\"[^\"]*\"/<q>/g")

# Destructive patterns, matched against quote-STRIPPED segments and the
# stripped whole. Command-position patterns use (^ *) on segments; env-var
# assignment prefixes are tolerated.
ENVP='([A-Za-z_][A-Za-z0-9_]*=[^ ]* +)*'
deny_patterns=(
  # rm aimed at dangerous roots only (not every absolute path — /tmp/scratch
  # and project-tree absolute paths are legitimate)
  'rm +(-[a-zA-Z]+ +)*-?[a-zA-Z]*rf? +/+( |$)'
  'rm +-rf +/(bin|boot|dev|etc|home|lib|lib64|opt|sbin|srv|sys|usr|var|System|Library|Users|Applications)(/| |$)'
  'rm +-rf +~'
  'rm +-rf +\$HOME'
  # Fork bomb
  ':\(\) *\{ *:\|:& *\} *;:'
  # Disk-destroying
  'dd +if='
  'mkfs\.'
  'sudo +rm'
  # Pipe-to-shell from network
  'curl .*\| *(sh|bash|zsh)'
  'wget .*\| *(sh|bash|zsh)'
  # Piping file CONTENT into a shell (security-automode-2)
  'cat +[^|]*\| *(sh|bash|zsh)( |$|<)'
  # Indirect execution paths
  'base64 +(-d|--decode) +.* *\| *(sh|bash|zsh)'
  'echo +.* *\| *base64 +-d *\| *(sh|bash|zsh)'
  # Process substitution as a code source, regardless of the head command
  '(^| )(\.|source|bash|sh|zsh) +<\('
  'source +/dev/stdin'
  # Decode-then-pipe-to-shell variants beyond base64 (hex via xxd / printf).
  'xxd +(-r|-p|-rp|-r -p|-p -r).* *\| *(sh|bash|zsh)'
  'printf +.* *\| *(sh|bash|zsh)'
  'openssl +(base64|enc) +.*(-d|-base64).* *\| *(sh|bash|zsh)'
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

# Command-position patterns: only dangerous when they ARE the command, not when
# they appear in arguments or prose. Checked with a ^-anchor per segment.
deny_cmdpos_patterns=(
  "${ENVP}eval( +|\$)"
  "${ENVP}exec +"
  "${ENVP}python3? +-c( +|\$|<)"
  "${ENVP}perl +-e( +|\$|<)"
  "${ENVP}node +(-e|--eval)( +|\$|<)"
  "${ENVP}ruby +-e( +|\$|<)"
  "${ENVP}(sh|bash|zsh) +-c( +|\$|<)"
)

# Raw-side patterns (checked against the UNstripped whole): writes to
# constitution-class files where the path may be quoted — quote-stripping would
# otherwise open a trivial `tee ".claude/hooks/x"` hole. Quote-tolerant forms.
deny_raw_patterns=(
  'tee +(-a +)?"?\.claude/'
  "tee +(-a +)?'?\\.claude/"
  'find +.*-exec +(sh|bash|zsh)'
  'xargs +.*(sh|bash|zsh)'
  '>+ +"?\.claude/hooks/'
  '>+ +"?\.claude/CLAUDE\.md'
  '>+ +"?\.claude/settings\.json'
  '>+ +"?\.github/workflows/'
)

deny() {
  # JSON built with jq: patterns contain backslashes that are invalid JSON
  # escapes when interpolated raw (pre-existing defect fixed in this rescope).
  local reason="Blocked by .claude/hooks/pre-bash-guard.sh: $1. If you intended this, run it interactively in a shell, not through the agent."
  jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  echo "$reason" >&2
  exit 2
}

# Pre-pass: command/process substitution that wraps a dangerous payload.
# `bash -c "$(curl …)"`, `echo $(curl …|bash)`, `echo \`curl …\`` and
# `<(curl …)` all smuggle a network-fetch-then-execute past the per-segment
# split. Checked on the RAW normalized command (the payload hides in quotes).
subst_sink_patterns=(
  '\$\([^)]*(curl|wget|fetch)'
  '`[^`]*(curl|wget|fetch)'
  '<\([^)]*(curl|wget|fetch)'
  '\$\([^)]*(curl|wget)[^)]*\|[^)]*(sh|bash|zsh)'
)
for pattern in "${subst_sink_patterns[@]}"; do
  if [[ "$cmd_normalized" =~ $pattern ]]; then
    deny "command/process substitution smuggles a network-fetch-or-shell payload (pattern /$pattern/)"
  fi
done

for pattern in "${deny_raw_patterns[@]}"; do
  if [[ "$cmd_normalized" =~ $pattern ]]; then
    deny "command matches constitution-write pattern /$pattern/"
  fi
done

# Variable indirection of a destructive payload (BYPASS-03): an assignment whose
# value embeds a destructive verb, later executed as a bare $VAR. The payload
# lives inside quotes (invisible after stripping), so detect the assignment on
# the RAW command and the bare-$VAR execution on the stripped command.
if [[ "$cmd_normalized" =~ [A-Za-z_][A-Za-z0-9_]*=[\'\"]?[^\'\"]*(rm\ -rf|curl\ |wget\ |mkfs|dd\ if=) ]] \
   && [[ "$cmd_stripped" =~ (^|[\;\&\|]\ *)\"?\$\{?[A-Za-z_] ]]; then
  deny "variable assignment smuggles a destructive payload executed via \$VAR indirection"
fi

# Split the quote-stripped command on chaining delimiters (;, &&, ||, |) so each
# segment is checked independently. Quoted spans are already collapsed to <q>,
# so a delimiter inside quotes can no longer create a bogus split.
IFS=$'\n' read -r -d '' -a segments < <(printf '%s' "$cmd_stripped" | sed -E 's/[;|&]+/\n/g' ; printf '\0')

check_segment() {
  local seg="$1"
  for pattern in "${deny_patterns[@]}"; do
    if [[ "$seg" =~ $pattern ]]; then
      deny "segment '$seg' matches destructive pattern /$pattern/"
    fi
  done
}

check_cmdpos() {
  # Command-position check: pattern must match at the START of the segment
  # (after leading whitespace).
  local seg="$1"
  while [ "$seg" != "${seg# }" ]; do seg="${seg# }"; done
  for pattern in "${deny_cmdpos_patterns[@]}"; do
    if [[ "$seg" =~ ^$pattern ]]; then
      deny "segment '$seg' invokes a blocked interpreter/exec form at command position (pattern /^$pattern/)"
    fi
  done
}

# Check each segment AND the stripped whole (catches pipe patterns that span splits).
for seg in "${segments[@]}"; do
  check_segment "$seg"
  check_cmdpos "$seg"
done
check_segment "$cmd_stripped"

# Patterns that should always ask (even if not in settings.ask). Checked on the
# stripped command so quoted prose cannot trigger them.
ask_patterns=(
  '^rm[[:space:]]+-rf[[:space:]]'
  'git[[:space:]]+push.*--force'
  'git[[:space:]]+push.*-f[[:space:]]'
  'docker[[:space:]]+system[[:space:]]+prune'
  # Generic content-piped-into-shell not already denied (e.g. `jq -r .x f | sh`)
  '[^|]\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)'
  # $VAR indirection of a destructive/network verb: `$CMD -rf …`, `$FETCH http…`
  '^[[:space:]]*"?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"? .*(-rf|https?://)'
)

for pattern in "${ask_patterns[@]}"; do
  if [[ "$cmd_stripped" =~ $pattern ]]; then
    jq -n --arg r "Sensitive command — confirm intent. Pattern: '$pattern'" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
    exit 0
  fi
done

exit 0
