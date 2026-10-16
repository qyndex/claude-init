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
# Shell-literal quotes, comments and quoted heredoc bodies cannot change active
# backtick pairing. Heredoc bodies receive their own conservative raw scan;
# even cat can write a script that a later command executes. Unhandled syntax
# falls back to the original conservative raw check; guessing about quote state could hide a real substitution.
# Bound the supported quote/body profile before any per-character or body work.
# Larger submissions retain the original raw matcher; no bytes are truncated.
if [ "${#cmd}" -gt 32768 ]; then
  backtick_payloads="fallback"
elif ! backtick_payloads=$(printf '%s\n' "$cmd" | awk -v sq="'" '
  # Only mask frontend fetch calls and a literal fetching word, never lines.
  # Retain every other byte, including adjacent network commands and ticks.
  function body_line(line, cleaned, prefix, literal, ending, chunk, suffix) {
    cleaned = line
    if (line ~ /^[[:space:]]*((export[[:space:]]+)?(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=|await[[:space:]]+|return[[:space:]]+|async[[:space:]]+function[[:space:]]+)/) {
      while (match(cleaned, /(^|[^[:alnum:]_$])fetch\(/)) {
        chunk = substr(cleaned, RSTART, RLENGTH)
        sub(/fetch\(/, "frontend_call(", chunk)
        cleaned = substr(cleaned, 1, RSTART - 1) chunk substr(cleaned, RSTART + RLENGTH)
      }
      # Restrict the prose word to the initial template value, not shell code
      # later on the same declaration line. Keep prefix/suffix names visible.
      if (match(cleaned, /^[[:space:]]*(const|let|var)[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*[[:space:]]*=[[:space:]]*`/)) {
        prefix = substr(cleaned, 1, RLENGTH)
        literal = substr(cleaned, RLENGTH + 1)
        ending = index(literal, "`")
        if (ending) {
          suffix = substr(literal, ending)
          literal = substr(literal, 1, ending - 1)
          while (match(literal, /(^|[^[:alnum:]_])fetching([^[:alnum:]_]|$)/)) {
            chunk = substr(literal, RSTART, RLENGTH)
            sub(/fetching/, "frontend_text", chunk)
            literal = substr(literal, 1, RSTART - 1) chunk substr(literal, RSTART + RLENGTH)
          }
          cleaned = prefix literal suffix
        }
      }
    }
    return cleaned
  }
  function inspect_body() {
    if (body ~ /`[^`]*(curl|wget|fetch)/) body_network = 1
    body = ""
  }
  BEGIN {
    heredoc_pattern = "<<-?[[:space:]]*(" sq "[A-Za-z_][A-Za-z0-9_]*" sq "|\"[A-Za-z_][A-Za-z0-9_]*\")"
  }
  {
    if (here != "") {
      ending = $0
      if (strip_tabs) sub(/^\t+/, "", ending)
      if (ending == here) { inspect_body(); here = "" }
      else body = body body_line($0) "\n"
      next
    }
    line = $0
    has_here = index(line, "<<") > 0
    here_start = 0
    # A here-string must never start a body, even if its suffix resembles <<.
    if (index(line, "<<<")) ambiguous = 1
    if (has_here && !index(line, "<<<") && match(line, heredoc_pattern)) {
      here_start = RSTART
      redirection = substr(line, RSTART, RLENGTH)
      rest = substr(line, RSTART + RLENGTH)
      if (index(substr(line, 1, RSTART - 1), "<<") || index(rest, "<<") ||
          (rest != "" && substr(rest, 1, 1) !~ /[[:space:]]/)) here_start = 0
      delimiter = redirection
      sub(/^<<-?[[:space:]]*/, "", delimiter)
      delimiter = substr(delimiter, 2, length(delimiter) - 2)
    }
    if (index(line, "$(") || index(line, "<(") || index(line, "${") || index(line, "$[") ||
        index(line, "((") || index(line, "[[") ||
        index(line, "$" sq) || index(line, "$\"")) ambiguous = 1
    if (line ~ /\\$/) ambiguous = 1
    for (i = 1; i <= length(line); i++) {
      ch = substr(line, i, 1)
      if (quote == "single") {
        # Quoted text may later feed a shell through a file, pipe or wrapper.
        # Inspect its own tick pairs without changing outer shell tick state.
        if (ch == sq) {
          if (literal_inside || (literal_escape && literal_tick)) ambiguous = 1
          quote = ""
          literal_inside = 0
          literal_payload = ""
        } else if (ch == "`") {
          literal_tick = 1
          if (literal_inside) {
            payloads = payloads literal_payload "\n"
            literal_inside = 0
            literal_payload = ""
          } else { literal_inside = 1; literal_payload = "" }
        } else {
          if (ch == "\\") literal_escape = 1
          if (literal_inside) literal_payload = literal_payload ch
        }
        continue
      }
      if (inside) {
        if (ch == sq || ch == "\"") ambiguous = 1
        if (ch == "`" && !escaped) {
          payloads = payloads payload "\n"
          inside = 0
          payload = ""
        } else payload = payload ch
        if (ch == "\\") escaped = !escaped
        else escaped = 0
        continue
      }
      if (escaped) { escaped = 0; continue }
      if (ch == "\\") { ambiguous = 1; escaped = 1; continue }
      if (i == here_start && quote == "") {
        next_here = delimiter
        next_strip = index(redirection, "<<-") == 1
        has_here = 0
      }
      if (ch == sq && quote == "") {
        quote = "single"
        literal_escape = 0
        literal_tick = 0
        continue
      }
      if (ch == "\"") {
        if (quote == "double") quote = ""
        else quote = "double"
        continue
      }
      # Unquoted extglob patterns have context-sensitive boundaries: use raw fallback.
      if (quote == "" && ch ~ /[@!?+*]/ && substr(line, i + 1, 1) == "(") ambiguous = 1
      if (ch == "#" && quote == "" &&
          (i == 1 || substr(line, i - 1, 1) ~ /[ \t;]/)) break
      if (ch == "`") { inside = 1; payload = "" }
    }
    if (has_here) ambiguous = 1
    if (next_here != "") { here = next_here; strip_tabs = next_strip; next_here = "" }
    if (inside) payload = payload " "
    if (literal_inside) literal_payload = literal_payload " "
    escaped = 0
  }
  END {
    if (inside || quote != "" || here != "") ambiguous = 1
    print body_network ? "body-network" : (ambiguous ? "fallback" : "parsed")
    printf "%s", payloads
  }
'); then
  deny "cannot inspect backtick substitutions; failing closed"
fi
backtick_mode="${backtick_payloads%%$'\n'*}"
case "$backtick_mode" in
  parsed) ;;
  body-network) deny "quoted heredoc contains a backtick network payload" ;;
  fallback)
    backtick_fallback='`[^`]*(curl|wget|fetch)'
    if [[ "$cmd_normalized" =~ $backtick_fallback ]]; then
      deny "ambiguous shell quoting contains a backtick network payload"
    fi
    ;;
  *) deny "invalid backtick inspection result; failing closed" ;;
esac
# Preserve legacy substring denials for active shell payloads and aliases.
# Frontend fetch exceptions are scoped to body data above, never active code.
backtick_network='(curl|wget|fetch)'
if [[ "$backtick_payloads" =~ $backtick_network ]]; then
  deny "backtick substitution contains a network executable token"
fi
subst_sink_patterns=(
  '\$\([^)]*(curl|wget|fetch)'
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

# SQL is executable content for database clients even when quoted. Match the
# client on stripped command positions so ordinary quoted prose stays content.
sql_client_pattern="(^|[;|&] *)${ENVP}(psql|mysql|sqlite3|sqlcmd)( |$)"
if [[ "$cmd_stripped" =~ $sql_client_pattern ]]; then
  sql_upper=$(printf '%s' "$cmd_normalized" | tr '[:lower:]' '[:upper:]')
  if [[ "$sql_upper" =~ (DROP[[:space:]]+(TABLE|DATABASE)|TRUNCATE[[:space:]]+TABLE|DELETE[[:space:]]+FROM) ]]; then
    deny "database client contains destructive SQL; quoted SQL is executable input"
  fi
fi

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
