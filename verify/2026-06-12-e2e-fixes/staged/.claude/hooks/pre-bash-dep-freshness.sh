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

# Quick filter: only fire on install-class commands.
# e2e-audit security-automode-2: ephemeral-exec verbs (npx/uvx/bunx/pnpx/pipx,
# pnpm dlx, uv tool run) download-and-RUN a package in one step — the same
# supply-chain surface as an install, so they get the same registry+OSV check.
ephemeral=""
case "$cmd" in
  *"npm install"*|*"npm i "*|*"npm add"*|*"npm i@"*) ecosystem=npm ;;
  *"pnpm add"*|*"pnpm install"*|*"yarn add"*) ecosystem=npm ;;
  *"pip install"*|*"pip3 install"*) ecosystem=PyPI ;;
  *"uv add"*|*"uv pip install"*) ecosystem=PyPI ;;
  *"cargo add"*|*"cargo install"*) ecosystem=crates.io ;;
  *"go get"*|*"go install"*) ecosystem=Go ;;
  *"npx "*) ecosystem=npm; ephemeral=npx ;;
  *"bunx "*) ecosystem=npm; ephemeral=bunx ;;
  *"pnpx "*) ecosystem=npm; ephemeral=pnpx ;;
  *"pnpm dlx "*) ecosystem=npm; ephemeral="pnpm dlx" ;;
  *"uvx "*) ecosystem=PyPI; ephemeral=uvx ;;
  *"uv tool run "*) ecosystem=PyPI; ephemeral="uv tool run" ;;
  *"pipx run "*|*"pipx install "*) ecosystem=PyPI; ephemeral=pipx ;;
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

# Ephemeral-exec parse: the package is the FIRST non-flag token after the verb
# (`npx create-foo@2 my-app` runs create-foo, not my-app — the last-positional
# heuristic used for installs picks the wrong token here).
if [ -n "$ephemeral" ]; then
  rest="${cmd#*$ephemeral }"
  for tok in $rest; do
    case "$tok" in
      -*) continue ;;
      run|install) continue ;;
      *) pkg_tok="$tok"; break ;;
    esac
  done
  pkg_tok="${pkg_tok:-}"
  if [ -z "$pkg_tok" ]; then exit 0; fi
  case "$pkg_tok" in
    *@*[0-9]*) pkg="${pkg_tok%@*}"; requested_ver="${pkg_tok##*@}" ;;
    *==*) pkg="${pkg_tok%%==*}"; requested_ver="${pkg_tok##*==}" ;;
    *) pkg="$pkg_tok"; requested_ver="latest" ;;
  esac
fi

[ -n "$pkg" ] || case "$ecosystem" in
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

# ─── Per-session verdict cache (e2e-audit hooks-engineering-5) ────────────
# Install-heavy loops re-probe the same pkg@ver every call — up to 15s each.
# Cache the DECISION (not the network data): file content is the exact JSON
# decision to replay; an empty file means "allow". Fail-closed asks are NOT
# cached — the network may recover. Keyed per session (or per day headless).
cache_dir=".claude/hooks/.log/dep-freshness-cache"
mkdir -p "$cache_dir"
cache_file="$cache_dir/${CLAUDE_SESSION_ID:-day-$(date +%Y%m%d)}-${ecosystem}-${pkg//\//_}-${requested_ver}"
if [ -f "$cache_file" ]; then
  cat "$cache_file"
  exit 0
fi

# Test hook: simulate an unreachable registry deterministically (no network).
if [ "${DEP_FRESHNESS_FORCE_OFFLINE:-0}" = "1" ]; then
  echo "$(date -Iseconds) forced-offline pkg=$pkg eco=$ecosystem" >> "$fallback_log"
  emit_ask "pre-bash-dep-freshness could not reach the ${ecosystem} registry to verify ${pkg}; failing closed (cannot prove the version is current or vuln-free). Confirm only if you trust this install."
fi
# Operator-declared airgap (hooks-engineering-5): probes are pointless against a
# local mirror — skip them and ALLOW, loudly logged. This is the documented
# operator escape (same contract class as LANE_GUARD=0), distinct from the
# fail-closed unreachable path which still asks.
if [ "${DEP_FRESHNESS_OFFLINE:-0}" = "1" ]; then
  echo "$(date -Iseconds) declared-offline pkg=$pkg eco=$ecosystem ver=$requested_ver (DEP_FRESHNESS_OFFLINE=1 — probes skipped by operator declaration)" >> "$fallback_log"
  exit 0
fi

# ─── Probes: registry + OSV, concurrent, 5s each (hooks-engineering-5) ────
# Sequential 10s+10s could overrun the 15s hook cap on slow networks, which
# FAILS OPEN at the harness layer. 5s concurrent probes keep worst-case ≤ ~10s
# (sequential only when "latest" must resolve first), inside the cap.
probe_registry() {
  case "$ecosystem" in
    # JUSTIFIED: curl noise is muted on purpose — a registry/network failure leaves latest empty, which the fail-closed/log branch below handles
    npm)       curl -fsSL --max-time 5 "https://registry.npmjs.org/${pkg}/latest" 2>/dev/null | jq -r '.version // empty' ;;
    # JUSTIFIED: same muted registry probe — an empty latest on failure is routed to the fallback handling below
    PyPI)      curl -fsSL --max-time 5 "https://pypi.org/pypi/${pkg}/json" 2>/dev/null | jq -r '.info.version // empty' ;;
    # JUSTIFIED: same muted registry probe for crates — an empty latest on failure is handled below
    crates.io) curl -fsSL --max-time 5 "https://crates.io/api/v1/crates/${pkg}" 2>/dev/null | jq -r '.crate.max_stable_version // empty' ;;
    Go)        printf '' ;;  # Go module proxy has no clean "latest" endpoint; skip live check
  esac
}
probe_osv() { # <version>
  local q
  q=$(jq -nc --arg pkg "$pkg" --arg eco "$ecosystem" --arg ver "$1" \
    '{package: {name: $pkg, ecosystem: $eco}, version: $ver}')
  # JUSTIFIED: curl noise muted on purpose — an OSV outage leaves the response empty, which the fail-closed guard below detects and turns into an ask
  curl -fsSL --max-time 5 -X POST "https://api.osv.dev/v1/query" \
    -H "Content-Type: application/json" -d "$q" 2>/dev/null
}

reg_tmp=$(mktemp); osv_tmp=$(mktemp)
trap 'rm -f "$reg_tmp" "$osv_tmp"' EXIT
probe_registry > "$reg_tmp" &
reg_pid=$!
osv_pid=""
if [ "$requested_ver" != "latest" ]; then
  # Explicit version → OSV doesn't need the registry result; run both at once.
  probe_osv "$requested_ver" > "$osv_tmp" &
  osv_pid=$!
fi
# JUSTIFIED: wait rc intentionally unused — an empty reg_tmp is the unreachable signal handled below
wait "$reg_pid" 2>/dev/null || true
latest=$(cat "$reg_tmp")

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

# ─── OSV result (already racing if the version was explicit) ──────────────
if [ -n "$osv_pid" ]; then
  # JUSTIFIED: wait rc intentionally unused — an empty osv_tmp is the unreachable signal handled below
  wait "$osv_pid" 2>/dev/null || true
else
  probe_osv "$requested_ver" > "$osv_tmp"
fi
osv_response=$(cat "$osv_tmp")

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
  tee "$cache_file" <<EOF
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
  tee "$cache_file" <<EOF
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

# All clear — cache the allow (empty file replays as silence)
: > "$cache_file"
exit 0
