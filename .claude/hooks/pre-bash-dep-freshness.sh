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
# Fail-CLOSED on network errors (Spec 001 AC-10): if the registry or OSV is
# unreachable we cannot prove the dependency is safe, so we emit
# permissionDecision:"ask" rather than silently allowing. In Auto Mode the
# Sonnet classifier resolves the ask; interactively the operator confirms.
# All fallbacks logged to .claude/hooks/.log/dep-freshness-fallback.log.
#
# Testing hook: DEP_FRESHNESS_FORCE_OFFLINE=1 simulates an unreachable registry
# without any real network call, so the fail-closed path is unit-testable.

set -uo pipefail

# Emit a permissionDecision:"ask" JSON decision and exit (fail-closed helper).
emit_ask() {
  local reason="$1"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "$reason"
  }
}
EOF
  exit 0
}

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

# No parseable package → let it through (e.g., `npm install` with no args runs
# against package.json). Subcommand verbs are not packages: a bare
# `npm install` / `pip install` / `cargo add` parses the verb as the trailing
# token, which must not be treated as a package to vuln-check.
case "$pkg" in
  install|i|add|get) exit 0 ;;
esac
if [ -z "$pkg" ] || [ "$pkg" = "$cmd" ]; then
  exit 0
fi

mkdir -p .claude/hooks/.log
fallback_log=".claude/hooks/.log/dep-freshness-fallback.log"

# ─── Query registry for latest version (10s timeout) ─────────────────────
latest=""
# Test hook: simulate an unreachable registry deterministically (no network).
if [ "${DEP_FRESHNESS_FORCE_OFFLINE:-0}" = "1" ]; then
  echo "$(date -Iseconds) forced-offline pkg=$pkg eco=$ecosystem" >> "$fallback_log"
  emit_ask "pre-bash-dep-freshness could not reach the ${ecosystem} registry to verify ${pkg}; failing closed (cannot prove the version is current or vuln-free). Confirm only if you trust this install."
fi
case "$ecosystem" in
  npm)
    # JUSTIFIED: curl noise is muted on purpose — a registry/network failure leaves latest empty, which the fail-closed/log branch below handles (this task only annotates; T-026 owns the network policy)
    latest=$(timeout 10 curl -fsSL "https://registry.npmjs.org/${pkg}/latest" 2>/dev/null | jq -r '.version // empty')
    ;;
  PyPI)
    # JUSTIFIED: same muted registry probe — an empty latest on failure is routed to the fallback handling below; this task does not alter that policy
    latest=$(timeout 10 curl -fsSL "https://pypi.org/pypi/${pkg}/json" 2>/dev/null | jq -r '.info.version // empty')
    ;;
  crates.io)
    # JUSTIFIED: same muted registry probe for crates — an empty latest on failure is handled below; annotation only
    latest=$(timeout 10 curl -fsSL "https://crates.io/api/v1/crates/${pkg}" 2>/dev/null | jq -r '.crate.max_stable_version // empty')
    ;;
  Go)
    # Go module proxy doesn't have a clean "latest" endpoint; skip live check
    latest=""
    ;;
esac

if [ -z "$latest" ]; then
  # Go has no clean "latest" endpoint — it legitimately skips the live version
  # check and proceeds to the OSV vuln query below. For registries we DO query
  # (npm/PyPI/crates), an empty result means unreachable → fail CLOSED (AC-10).
  if [ "$ecosystem" != "Go" ]; then
    echo "$(date -Iseconds) registry-unreachable pkg=$pkg eco=$ecosystem cmd=\"${cmd:0:100}\"" >> "$fallback_log"
    emit_ask "pre-bash-dep-freshness could not reach the ${ecosystem} registry to verify ${pkg}; failing closed (cannot prove the version is current or vuln-free). Confirm only if you trust this install."
  fi
fi

# Resolve "latest" → actual version
[ "$requested_ver" = "latest" ] && requested_ver="$latest"

# ─── Query OSV for vulnerabilities at requested version ──────────────────
osv_query=$(jq -nc \
  --arg pkg "$pkg" \
  --arg eco "$ecosystem" \
  --arg ver "$requested_ver" \
  '{package: {name: $pkg, ecosystem: $eco}, version: $ver}')

# JUSTIFIED: curl noise muted on purpose — an OSV outage leaves the response empty, which the fail-closed guard below detects and turns into an ask (the version cannot be proven vuln-free); annotation only, T-026 owns this policy
osv_response=$(timeout 10 curl -fsSL -X POST "https://api.osv.dev/v1/query" \
  -H "Content-Type: application/json" \
  -d "$osv_query" 2>/dev/null)

# Fail CLOSED if OSV is unreachable (empty body or non-JSON) — we cannot prove
# the version is free of known vulnerabilities, so we must ask, not allow (AC-10).
# JUSTIFIED: this is a validity test — a non-JSON or empty body makes jq exit non-zero, which is precisely the fail-closed trigger; muting jq's parse complaint is the point
if [ -z "$osv_response" ] || ! echo "$osv_response" | jq -e . >/dev/null 2>&1; then
  echo "$(date -Iseconds) osv-unreachable pkg=$pkg eco=$ecosystem ver=$requested_ver" >> "$fallback_log"
  emit_ask "pre-bash-dep-freshness could not reach OSV.dev to vuln-check ${pkg}@${requested_ver}; failing closed. Confirm only if you trust this install."
fi

# JUSTIFIED: response is already proven valid JSON above; muting here guards only against a missing .vulns key, defaulted to 0 by the line below (no known vulns)
vulns=$(echo "$osv_response" | jq -r '.vulns // [] | length' 2>/dev/null)
[ -z "$vulns" ] && vulns=0

# ─── Decide ──────────────────────────────────────────────────────────────
if [ "$vulns" -gt 0 ]; then
  # JUSTIFIED: extracting ids from the already-validated response for the deny message; a vuln lacking an id is cosmetically skipped and never blocks the deny decision
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
