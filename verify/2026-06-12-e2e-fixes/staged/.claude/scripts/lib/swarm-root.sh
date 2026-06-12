#!/usr/bin/env bash
# swarm-root.sh — single shared swarm root (e2e-audit swarm-1).
#
# Hooks running inside a `claude -w feat-N` worktree previously wrote .swarms/**
# relative to the WORKTREE, while the coordinator read from the MAIN checkout —
# events, stream state, and handoffs landed where nothing ever looked. This
# resolves the main checkout root via git-common-dir so every .swarms path is
# absolute and shared. No-op outside a git repo (falls back to $PWD) and in the
# main checkout itself (common dir is ./.git).
#
# Source this, then use:  "$SWARM_ROOT/.swarms/..."

swarm_root() {
  local common
  # JUSTIFIED: outside a git repo there is no common dir — $PWD keeps the caller's relative behavior
  common=$(git rev-parse --git-common-dir 2>/dev/null) || { pwd -P; return 0; }
  [ -z "$common" ] && { pwd -P; return 0; }
  case "$common" in
    /*) : ;;
    *) common="$(pwd)/$common" ;;
  esac
  # The main checkout root is the parent of the shared .git dir
  (cd "$(dirname "$common")" 2>/dev/null && pwd -P) || pwd -P
}

SWARM_ROOT="$(swarm_root)"
export SWARM_ROOT
