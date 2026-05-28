#!/usr/bin/env bash
# PreToolUse(Bash) hook — Round 8 A.
#
# Intercepts dependency-install commands (npm/pnpm/yarn install, pip install,
# uv add, cargo add, go get) and:
#   1. Queries the LIVE registry for the latest stable version
#   2. Queries OSV.dev for known vulnerabilities at the requested version
#   3. Hard-blocks (exit 2 via permissionDecision=deny) installs of vulnerable
#      versions
#   4. Warns when the requested version trails latest by >1 major
#
# Fail-open on network errors: a registry/OSV outage shouldn't block dev work.
# All fallbacks logged to .claude/hooks/.log/dep-freshness-fallback.log.

set -uo pipefail

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')

# Quick filter: only fire on install-class commands
case "$cmd" in
  *"npm install"*|*"npm i "*|*"npm add"*|*"npm i@"*) ecosystem=npm ;;
  *"pnpm add"*|*"pnpm install"*|*"yarn add"*) ecosystem=npm ;;
  *"pip install"*|*"pip3 install"*) ecosystem=PyPI ;;
  *"uv add"*|*"uv pip install"*) ecosystem=PyPI ;;
  *"cargo add"*|*"cargo install"*) ecosystem=crates.io ;;
  *"go get"*|*"go install"*) ecosystem=Go ;;
  *) exit 0 ;;
esac

# Parse package + version from command (best-effort)
# Patterns supported:
#   npm install foo@1.2.3 / foo / foo@latest
#   pip install foo==1.2.3 / foo>=1.2.0
#   cargo add foo@1.2.3 / foo --version 1.2.3
#   go get example.com/foo@v1.2.3

pkg=""
requested_ver=""
case "$ecosystem" in
  npm)
    # Extract the last positional arg that doesn't start with -
    arg=$(echo "$cmd" | grep -oE '[a-z@][a-zA-Z0-9_/.\-]*(@[a-zA-Z0-9_.\-]+)?' | tail -1)
    if echo "$arg" | grep -q '@.*[0-9]'; then
      pkg="${arg%@*}"
      requested_ver="${arg##*@}"
    else
      pkg="$arg"
      requested_ver="latest"
    fi
    ;;
  PyPI)
    arg=$(echo "$cmd" | grep -oE '[a-zA-Z][a-zA-Z0-9_\-]*(==[0-9][0-9a-z_.\-]*)?' | tail -1)
    if echo "$arg" | grep -q '=='; then
      pkg="${arg%%==*}"
      requested_ver="${arg##*==}"
    else
      pkg="$arg"
      requested_ver="latest"
    fi
    ;;
  crates.io)
    arg=$(echo "$cmd" | grep -oE 'cargo (add|install) [a-zA-Z0-9_\-]+' | awk '{print $NF}')
    pkg="$arg"
    requested_ver=$(echo "$cmd" | grep -oE '@[0-9][0-9a-z_.\-]*|--version[= ][0-9][0-9a-z_.\-]*' | grep -oE '[0-9][0-9a-z_.\-]*$' | head -1)
    [ -z "$requested_ver" ] && requested_ver="latest"
    ;;
  Go)
    arg=$(echo "$cmd" | grep -oE '[a-z][a-z0-9_.\-]*/[a-zA-Z0-9_/.\-]+(@v?[0-9][0-9a-z_.\-]*)?' | tail -1)
    if echo "$arg" | grep -q '@'; then
      pkg="${arg%@*}"
      requested_ver="${arg##*@}"
    else
      pkg="$arg"
      requested_ver="latest"
    fi
    ;;
esac

# No parseable package → let it through (e.g., `npm install` with no args runs against package.json)
if [ -z "$pkg" ] || [ "$pkg" = "$cmd" ]; then
  exit 0
fi

mkdir -p .claude/hooks/.log
fallback_log=".claude/hooks/.log/dep-freshness-fallback.log"

# ─── Query registry for latest version (10s timeout) ─────────────────────
latest=""
case "$ecosystem" in
  npm)
    latest=$(timeout 10 curl -fsSL "https://registry.npmjs.org/${pkg}/latest" 2>/dev/null | jq -r '.version // empty')
    ;;
  PyPI)
    latest=$(timeout 10 curl -fsSL "https://pypi.org/pypi/${pkg}/json" 2>/dev/null | jq -r '.info.version // empty')
    ;;
  crates.io)
    latest=$(timeout 10 curl -fsSL "https://crates.io/api/v1/crates/${pkg}" 2>/dev/null | jq -r '.crate.max_stable_version // empty')
    ;;
  Go)
    # Go module proxy doesn't have a clean "latest" endpoint; skip live check
    latest=""
    ;;
esac

if [ -z "$latest" ]; then
  echo "$(date -Iseconds) registry-unreachable pkg=$pkg eco=$ecosystem cmd=\"${cmd:0:100}\"" >> "$fallback_log"
  # Fail-open: don't block dev work on a network blip
  exit 0
fi

# Resolve "latest" → actual version
[ "$requested_ver" = "latest" ] && requested_ver="$latest"

# ─── Query OSV for vulnerabilities at requested version ──────────────────
osv_query=$(jq -nc \
  --arg pkg "$pkg" \
  --arg eco "$ecosystem" \
  --arg ver "$requested_ver" \
  '{package: {name: $pkg, ecosystem: $eco}, version: $ver}')

osv_response=$(timeout 10 curl -fsSL -X POST "https://api.osv.dev/v1/query" \
  -H "Content-Type: application/json" \
  -d "$osv_query" 2>/dev/null)

vulns=$(echo "$osv_response" | jq -r '.vulns // [] | length' 2>/dev/null)
[ -z "$vulns" ] && vulns=0

# ─── Decide ──────────────────────────────────────────────────────────────
if [ "$vulns" -gt 0 ]; then
  vuln_ids=$(echo "$osv_response" | jq -r '.vulns[].id' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked by pre-bash-dep-freshness: ${pkg}@${requested_ver} has ${vulns} known vulnerabilities in OSV ($vuln_ids). Latest stable is ${latest}. Update version or document an OVERRIDE: <CVE-id> <reason> in the install command."
  }
}
EOF
  exit 0
fi

# Warn if requested version trails latest by major
warn=""
if [ "$requested_ver" != "$latest" ]; then
  req_major=$(echo "$requested_ver" | grep -oE '^[0-9]+' | head -1)
  latest_major=$(echo "$latest" | grep -oE '^[0-9]+' | head -1)
  if [ -n "$req_major" ] && [ -n "$latest_major" ] && [ "$((latest_major - req_major))" -ge 1 ]; then
    warn="${pkg}@${requested_ver} trails latest stable ${latest} by ${req_major}→${latest_major} (major). Consider the newest unless pinning intentionally."
  fi
fi

if [ -n "$warn" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "$warn"
  }
}
EOF
  exit 0
fi

# All clear
exit 0
