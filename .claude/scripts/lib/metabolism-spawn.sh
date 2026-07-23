#!/usr/bin/env bash
# metabolism-spawn.sh — the single seam every background `claude -p` metabolism
# spawn (dream / instinct / witness) goes through. M-01b of the 2026-07 memory
# implementation plan.
#
# WHY THIS EXISTS
#   The three spawns used `claude -p --bare`, which the 2026-07 audit found 100%
#   dead: `--bare` is "Minimal mode … Anthropic auth is strictly ANTHROPIC_API_KEY
#   or apiKeyHelper via --settings (OAuth and keychain are never read)" (CLI help).
#   The operator authenticates with OAuth, not an API key — so --bare can NEVER
#   read their credentials. The fix is to drop --bare so the OAuth session is used.
#
#   Two forms were tested on 2026-07-23 and BOTH fail auth (do NOT reintroduce):
#     claude -p --bare 'ok'                    → "Not logged in", exit 1
#     CLAUDE_CODE_SIMPLE=1 claude -p 'ok'      → "Not logged in", exit 1
#   CLAUDE_CODE_SIMPLE=1 suppresses OAuth identically to the flag. So the lean
#   spawn mode is forfeited: this seam runs a FULL `claude -p` (loads hooks/LSP/
#   plugins/CLAUDE.md) which is heavyweight and can hang — hence the mandatory
#   portable timeout below.
#
# CONTRACT
#   metabolism_spawn <timeout_secs> [claude-args...]
#     - invokes `claude -p` with NO --bare flag and NO CLAUDE_CODE_SIMPLE in env
#     - wraps the call in a portable timeout (timeout → gtimeout → bash watchdog)
#     - returns claude's exit code (124 if the timeout fired); callers MUST gate
#       state stamping on rc==0 so a failed spawn never records false success.
#   Reads stdin/stdout/stderr straight through — caller redirects to its log.

# Resolve a portable timeout runner. Stock macOS ships neither `timeout` nor
# `gtimeout`; fall back to a bash-native watchdog so the witness spawn no longer
# dies "command not found" before claude even starts.
_metabolism_timeout() {
  local secs="$1"; shift
  local t
  # Resolve to an actually-EXECUTABLE timeout; `command -v` can return a
  # present-but-non-executable file on some shells, so verify with -x.
  t=$(command -v timeout 2>/dev/null); if [ -n "$t" ] && [ -x "$t" ]; then
    "$t" "$secs" "$@"; return $?
  fi
  t=$(command -v gtimeout 2>/dev/null); if [ -n "$t" ] && [ -x "$t" ]; then
    "$t" "$secs" "$@"; return $?
  fi
  # bash watchdog: run the command backgrounded, kill it if it overruns.
  "$@" & local cmd_pid=$!
  ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) & local wd_pid=$!
  local rc=0
  wait "$cmd_pid" 2>/dev/null || rc=$?
  # If the watchdog is still alive, the command finished first — clean it up.
  kill -TERM "$wd_pid" 2>/dev/null
  wait "$wd_pid" 2>/dev/null || true
  # Normalize a kill-by-watchdog (143 = 128+SIGTERM) to timeout's 124 convention.
  [ "$rc" -eq 143 ] && rc=124
  return "$rc"
}

# The seam. NOTE: no --bare, and we explicitly unset CLAUDE_CODE_SIMPLE for the
# child so an inherited value from the parent shell can't silently kill OAuth.
metabolism_spawn() {
  local secs="$1"; shift
  # JUSTIFIED: env -u strips CLAUDE_CODE_SIMPLE from the child only; both --bare
  # and this var suppress OAuth (tested 2026-07-23), and OAuth is the credential
  # the operator uses. The full (non-bare) spawn is why the timeout is mandatory.
  _metabolism_timeout "$secs" env -u CLAUDE_CODE_SIMPLE claude -p "$@"
}
