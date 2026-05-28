#!/usr/bin/env bash
# Setup script — adopt the harness in a new repo.
# Run once after copying .claude/ into your project.
#
# Honest time estimate: 30-50 min including manual GitHub steps that follow.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

step() { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; exit 1; }
note() { printf '    %s\n' "$*"; }

step "Detecting environment"
command -v git >/dev/null || fail "git not installed"
command -v jq  >/dev/null || warn "jq not installed — REQUIRED for hooks. brew install jq / apt install jq"
command -v gh  >/dev/null || warn "gh not installed — REQUIRED for /ship, ruleset, PR automation. https://cli.github.com/"
command -v claude >/dev/null || warn "claude CLI not installed — install from https://code.claude.com before continuing"
ok "core tools detected"

step "Brownfield collision guard (Round 14)"
# If this repo already has a NON-factory CLAUDE.md, greenfield setup would clobber/half-merge it.
# Redirect to the adoption flow instead. Override with FORCE_GREENFIELD=1.
# JUSTIFIED: the muted grep just classifies the existing CLAUDE.md; a non-match (factory marker absent) is exactly the brownfield case we want to catch
if [ -f .claude/CLAUDE.md ] && ! grep -q "Karpathy's Four Principles" .claude/CLAUDE.md 2>/dev/null && [ "${FORCE_GREENFIELD:-0}" != "1" ]; then
  warn "Detected a non-factory .claude/CLAUDE.md — this looks like a BROWNFIELD repo."
  note "Don't run greenfield setup over it. Reconcile first, then adopt:"
  note "  bash <factory-clone>/.claude/scripts/reconcile-claude-dir.sh --from <factory-clone> --into ."
  note "  then run:  /adopt start        (full guide: docs/ADOPTION.md)"
  note "Override (treat as greenfield anyway): FORCE_GREENFIELD=1 bash .claude/scripts/setup.sh"
  fail "halting — use the brownfield adoption flow, not greenfield setup"
fi
ok "no foreign .claude/CLAUDE.md collision"

step "Initializing git (if needed)"
if [ ! -d .git ]; then
  git init -b main
  ok "initialized git repo"
else
  ok "git repo already present"
fi

step "Making scripts and hooks executable"
# JUSTIFIED: the redirect and fallback tolerate a glob that matches nothing (e.g. no .claude/skills/*.sh in a fresh install); chmod of the dirs that DO exist still runs
chmod +x .claude/hooks/*.sh .claude/statuslines/*.sh .claude/scripts/*.sh .claude/skills/*.sh 2>/dev/null || true
ok "scripts chmod +x"

step "Pre-creating runtime directories"
mkdir -p .claude/hooks/.log
mkdir -p .claude/memory/.cache/{checkpoints,active,archive,instincts}
mkdir -p .claude/worktrees
mkdir -p .swarms/{coordinator,streams,templates}
mkdir -p verify
touch .claude/hooks/.log/.gitkeep
ok "runtime directories ready"

step "Creating .gitignore entries"
ensure_ignore() {
  local p="$1"
  # JUSTIFIED: the muted grep tests whether the ignore entry already exists; a non-match (or absent .gitignore) is the trigger to append it, which is intended
  if [ ! -f .gitignore ] || ! grep -qxF "$p" .gitignore 2>/dev/null; then
    printf '%s\n' "$p" >> .gitignore
    ok "added '$p' to .gitignore"
  fi
}
ensure_ignore ".claude/settings.local.json"
ensure_ignore ".claude/hooks/.log/"
ensure_ignore ".claude/worktrees/"
ensure_ignore ".claude/memory/.cache/checkpoints/"
ensure_ignore ".claude/memory/.cache/active/"
ensure_ignore ".claude/memory/.cache/archive/"
ensure_ignore ".claude/memory/.cache/instincts/observations.jsonl"
ensure_ignore ".claude/memory/.cache/.*"
ensure_ignore ".swarms/coordinator/fleet.json"
ensure_ignore ".swarms/coordinator/workflow-state.json"
ensure_ignore ".swarms/streams/*"
ensure_ignore "!.swarms/streams/.gitkeep"
ensure_ignore "verify/"
ensure_ignore "OVERNIGHT_REPORT.md"
ensure_ignore "overnight-report-*.md"
ensure_ignore "node_modules/"
ensure_ignore ".venv/"
ensure_ignore "__pycache__/"
ensure_ignore "*.pyc"
ensure_ignore ".env"
ensure_ignore ".env.*"
ensure_ignore "!.env.example"

step "Seeding empty settings.local.json"
if [ ! -f .claude/settings.local.json ]; then
  cat > .claude/settings.local.json <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "_comment": "Personal overrides. Not committed. Use to add personal allow patterns, override model, etc.",
  "permissions": {
    "allow": [],
    "ask": [],
    "deny": []
  }
}
EOF
  ok "created settings.local.json"
fi

step "Verifying CLAUDE.md is loadable"
[ -f .claude/CLAUDE.md ] && ok "CLAUDE.md present" || warn ".claude/CLAUDE.md missing"

step "Verifying MCP config"
[ -f .mcp.json ] && jq -e . .mcp.json >/dev/null && ok ".mcp.json valid JSON" || warn ".mcp.json missing or invalid"

step "Optional toolchain checks"
command -v gitleaks >/dev/null || warn "gitleaks not installed (recommended): brew install gitleaks"
command -v prettier >/dev/null || command -v npx >/dev/null || warn "prettier/npx not available — format hook will no-op"
command -v shellcheck >/dev/null || warn "shellcheck not installed (recommended for harness-validate workflow)"
command -v ccusage >/dev/null || command -v npx >/dev/null || warn "ccusage not installed — token monitoring will be limited"
command -v semgrep >/dev/null || warn "semgrep not installed (recommended for in-agent SAST): brew install semgrep"

step "Initial validation"
bash .claude/scripts/validate.sh

step "Installing canonical plugins (this is the step earlier versions skipped)"
if command -v claude >/dev/null 2>&1; then
  if [ "${SKIP_PLUGINS:-0}" = "1" ]; then
    warn "SKIP_PLUGINS=1 set — skipping plugin install. Run bash .claude/scripts/install-plugins.sh later."
  else
    note "Installing: superpowers, skill-creator, mcp-builder, frontend-design, webapp-testing, doc-coauthoring, dream, token-optimizer, chrome-devtools-mcp, playwright, github, sentry"
    note "This takes ~3-5 minutes. To skip: SKIP_PLUGINS=1 bash .claude/scripts/setup.sh"
    bash .claude/scripts/install-plugins.sh || warn "plugin install had errors — re-run bash .claude/scripts/install-plugins.sh"
  fi
else
  warn "claude CLI not found — skipping plugin install. Install Claude Code first, then run bash .claude/scripts/install-plugins.sh"
fi

step "Optional: apply branch protection ruleset"
note "Branch protection is configured at .github/rulesets/main-protection.json"
note "To apply (requires gh + repo admin):"
note "  gh api repos/:owner/:repo/rulesets --method POST --input .github/rulesets/main-protection.json"
note "Skipping by default — run AFTER your CI workflows have run at least once on main"
note "(otherwise required-check names won't be available to reference in the ruleset)."

step "Setup complete"
cat <<'EOF'

Next steps (realistic ~30 min total):
  1. Install Claude Code CLI if not done: https://code.claude.com (~2 min)
  2. Open this project in Claude Code: `claude` (session-start hook greets you)
  3. Read .claude/CLAUDE.md (~3 min) — the constitution
  4. Try the onboarding tour: `/onboard` (interactive, ~10 min)
  5. First feature:
       /constitution    (if first-time tightening the constitution; ~3 min)
       /specify "..."   (~3-10 min for the agent to draft a spec)
       /plan            (~3-5 min)
       /tasks           (~1 min)
       /implement next  (per-task, ~2-5 min each)
       /verify          (~5 min)
       /review          (~3 min)
       /ship            (~2 min + CI time)

For 11 PM overnight autopilot:
  1. Read docs/AUTOPILOT.md
  2. Configure a Cloud Routine at https://claude.ai/code/routines
     (requires Claude Build plan or higher)
  3. Optionally install local desktop dream-cron backstop:
       bash .claude/scripts/install-overnight-tasks.sh

For parallel swarm:
  1. Read docs/PARALLEL-SWARM.md
  2. /swarm:plan 5
  3. /swarm:dispatch --dry-run    (verify what would spawn)
  4. /swarm:dispatch              (spawn for real)
  5. /swarm:status                (monitor)
  6. /swarm:merge                 (PR + CI + merge)
EOF
