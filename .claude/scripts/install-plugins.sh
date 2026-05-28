#!/usr/bin/env bash
# Bulk-install the recommended plugin set from .claude/plugins/marketplace.json.
# Idempotent — safe to re-run after pulling harness updates.
#
# Failure policy:
#   - superpowers install failure is FATAL (core dependency)
#   - other failures are warnings (you can re-run)

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

step() { printf '\n→ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*"; exit 1; }

if ! command -v claude >/dev/null 2>&1; then
  echo "Claude Code CLI not found. Install from https://code.claude.com first."
  exit 1
fi

CRITICAL_FAILURES=0

step "Adding marketplaces"
add_marketplace() {
  local mkt="$1"
  # JUSTIFIED: the redirect drops CLI chatter — a non-zero exit (already-added or transient fetch failure) is non-fatal and handled by the warn branch below
  if claude -p "/plugin marketplace add $mkt" --bare 2>/dev/null; then
    ok "$mkt"
  else
    warn "$mkt (already added or fetch failed — verify with /plugin marketplace list)"
  fi
}
add_marketplace "anthropics/claude-plugins-official"
add_marketplace "anthropics/claude-plugins-community"
add_marketplace "obra/superpowers-marketplace"
add_marketplace "wshobson/agents"
add_marketplace "grandamenium/dream-skill"
add_marketplace "alexgreensh/token-optimizer"

step "Installing CORE plugins (failure here is fatal)"
core_install() {
  local plugin="$1"
  # JUSTIFIED: the redirect drops CLI chatter only — the exit status is still honoured: a failure here routes to fail() which aborts, so this core install error is never silently swallowed
  if claude -p "/plugin install $plugin" --bare 2>/dev/null; then
    ok "$plugin"
  else
    fail "CRITICAL: $plugin failed to install. The harness depends on this plugin. Investigate and re-run."
  fi
}
core_install "superpowers@superpowers-marketplace"

step "Installing recommended plugins (failures here are non-fatal)"
optional_install() {
  local plugin="$1"
  # JUSTIFIED: the redirect drops CLI chatter — a non-zero exit (already-installed or transient fetch failure) is non-fatal for an optional plugin and handled by the warn branch below
  if claude -p "/plugin install $plugin" --bare 2>/dev/null; then
    ok "$plugin"
  else
    warn "$plugin (already installed or fetch failed — re-run later)"
  fi
}
for plugin in \
  "skill-creator@claude-plugins-official" \
  "mcp-builder@claude-plugins-official" \
  "frontend-design@claude-plugins-official" \
  "webapp-testing@claude-plugins-official" \
  "doc-coauthoring@claude-plugins-official" \
  "chrome-devtools-mcp@claude-plugins-official" \
  "playwright@claude-plugins-official" \
  "github@claude-plugins-official" \
  "sentry@claude-plugins-official" \
  "dream@dream-skill" \
  "token-optimizer@token-optimizer"
do
  optional_install "$plugin"
done

step "Installing Tier 3 memory (optional — claude-mem worker)"
if [ "${INSTALL_CLAUDE_MEM:-yes}" = "yes" ]; then
  if command -v npx >/dev/null 2>&1; then
    # JUSTIFIED: the redirect drops npx output — claude-mem is an optional Tier-3 component; a non-zero exit is non-fatal and surfaced by the warn branch below
    if npx -y claude-mem install 2>/dev/null; then
      ok "claude-mem worker installed (port 37777)"
    else
      warn "claude-mem install failed — re-run later or set INSTALL_CLAUDE_MEM=no"
    fi
  else
    warn "npx not available — skipping claude-mem"
  fi
fi

step "Verifying installed set"
# JUSTIFIED: the redirect drops CLI chatter — this is a best-effort summary listing at the end of the run; a non-zero exit just prints nothing and the script still completes
claude -p "/plugin list" --bare 2>/dev/null | head -50

step "Done"
cat <<'EOF'

Next:
  1. Restart Claude Code if it's running (`claude --continue` or fresh session)
  2. Verify with `/plugin list` and `/skill list`
  3. For optional plugins (designer-skills, marketing-skills, web-scraper):
       /plugin install <name>@wshobson-agents
  4. To skip claude-mem next time: INSTALL_CLAUDE_MEM=no bash .claude/scripts/install-plugins.sh
EOF
