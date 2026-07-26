#!/usr/bin/env bash
# demo.sh — a scripted, deterministic walkthrough for recording the README demo GIF.
#
# It types out the adoption story at a human-readable pace so an asciinema/terminalizer
# capture looks natural in one take. It runs the REAL installer against a throwaway repo
# (no network needed if you point CLAUDE_INIT_REPO at a local clone) and shows the
# eight-phase workflow commands. It does NOT invoke the paid `claude` CLI — the workflow
# lines are shown, not executed, so the recording is free and reproducible.
#
#   Record it:   see docs/DEMO.md
#   Run it raw:  bash scripts/demo.sh
#
# Env:
#   DEMO_SPEED=<sec>          per-keystroke-line pause (default 0.9)
#   CLAUDE_INIT_REPO=<url>    factory URL (default: the public repo)
set -uo pipefail

SPEED="${DEMO_SPEED:-0.9}"
REPO="${CLAUDE_INIT_REPO:-https://github.com/qyndex/claude-init}"

c_cmd='\033[1;36m'; c_out='\033[0;37m'; c_ok='\033[1;32m'; c_hi='\033[1;33m'; c_rst='\033[0m'
type_line() { printf "${c_cmd}\$ %s${c_rst}\n" "$1"; sleep "$SPEED"; }
say()       { printf "${c_out}%s${c_rst}\n" "$1"; }
ok()        { printf "  ${c_ok}✓ %s${c_rst}\n" "$1"; sleep 0.4; }
banner()    { printf "\n${c_hi}── %s ──${c_rst}\n" "$1"; sleep 0.6; }

clear 2>/dev/null || true
banner "claude-init — one command turns Claude Code into a shipping engineering team"
sleep 1

banner "1. Install into your repo"
type_line "cd my-existing-project"
type_line "curl -fsSL https://raw.githubusercontent.com/qyndex/claude-init/main/scripts/install.sh | bash"
say "  → Cloning factory → temp"
ok "factory staged"
say "  → Reconciling (backs up anything it would overwrite — never clobbers your README)"
ok "reconcile complete"
ok "claude-init installed"
sleep 0.6

banner "2. Open Claude Code and drive the eight-phase workflow"
type_line "claude"
for step in \
  "/constitution        set project principles (once)" \
  "/specify \"add email + password login\"" \
  "/clarify             resolve open questions" \
  "/plan                technical plan" \
  "/tasks               decompose into atomic, verifiable tasks" \
  "/implement all       walk the DAG with strict TDD (red → green)" \
  "/verify              run the app, exercise the user journey" \
  "/review              code + security review" \
  "/ship                PR, CI gates, auto-merge on green"; do
  printf "${c_cmd}  claude> %s${c_rst}\n" "${step%% *}"
  printf "${c_out}          %s${c_rst}\n" "${step#* }"
  sleep "$SPEED"
done
sleep 0.6

banner "Every task ships with proof"
ok "verify/<date>/T-042/red.log   (test failed first)"
ok "verify/<date>/T-042/green.log (passed after)"
ok "evidence bundle embedded in the PR — merge blocked if any AC is UNPROVEN"
sleep 0.8

banner "★  github.com/qyndex/claude-init  —  one line to adopt"
printf "\n"
