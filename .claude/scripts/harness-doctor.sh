#!/usr/bin/env bash
# Harness health check — AC-35.
# Runs the same structural checks as validate.sh but outputs machine-readable JSON.
# Used by harness-validate.yml to upload a structured artifact and by T-109.
#
# Usage:
#   bash .claude/scripts/harness-doctor.sh          # human-readable summary
#   bash .claude/scripts/harness-doctor.sh --json   # JSON array of check results

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

JSON_MODE=0
[ "${1:-}" = "--json" ] && JSON_MODE=1

result_file=$(mktemp)
trap 'rm -f "$result_file"' EXIT
printf '[\n' > "$result_file"
first_result=1

add_result() {
  local check="$1" status="$2" detail="$3"
  local entry
  entry=$(jq -nc --arg c "$check" --arg s "$status" --arg d "$detail" \
    '{check:$c,status:$s,detail:$d}')
  if [ "$first_result" -eq 1 ]; then
    first_result=0
    printf '%s\n' "$entry" >> "$result_file"
  else
    printf ',%s\n' "$entry" >> "$result_file"
  fi
  if [ "$JSON_MODE" -eq 0 ]; then
    [ "$status" = "pass" ] && printf '  ✓ %s\n' "$check" || printf '  ✗ %s: %s\n' "$check" "$detail"
  fi
}

[ "$JSON_MODE" -eq 0 ] && printf '\nHarness Doctor\n──────────────\n'

# Core files present
for f in .claude/CLAUDE.md .claude/settings.json .mcp.json tasks/TASKS.md; do
  if [ -f "$f" ]; then
    add_result "$f exists" "pass" ""
  else
    add_result "$f exists" "fail" "missing required file"
  fi
done

# JSON validity
for f in .claude/settings.json .mcp.json; do
  if [ -f "$f" ]; then
    if jq -e . "$f" > /dev/null 2>&1; then
      add_result "$f valid JSON" "pass" ""
    else
      add_result "$f valid JSON" "fail" "jq parse error"
    fi
  fi
done

# disableBypassPermissionsMode (nested under .permissions in this harness)
if [ -f .claude/settings.json ]; then
  val=$(jq -r '(.permissions.disableBypassPermissionsMode // .disableBypassPermissionsMode) // ""' .claude/settings.json 2>/dev/null)
  if [ "$val" = "disable" ]; then
    add_result "disableBypassPermissionsMode=disable" "pass" ""
  else
    add_result "disableBypassPermissionsMode=disable" "fail" "got: $val"
  fi
fi

# Hook executables
hook_fails=0
while IFS= read -r sh; do
  if [ ! -x "$sh" ]; then
    add_result "hook executable: $sh" "fail" "not executable"
    hook_fails=$((hook_fails + 1))
  fi
done < <(find .claude/hooks -name '*.sh' -type f 2>/dev/null)
[ "$hook_fails" -eq 0 ] && add_result "hooks executable" "pass" ""

# Constitution size
if [ -f .claude/CLAUDE.md ]; then
  lines=$(wc -l < .claude/CLAUDE.md | tr -d ' ')
  if [ "$lines" -le 300 ]; then
    add_result "constitution ≤300 lines" "pass" "${lines} lines"
  else
    add_result "constitution ≤300 lines" "fail" "${lines} lines (cap 300)"
  fi
fi

# @latest pins
if [ -f .mcp.json ] && command -v jq >/dev/null 2>&1; then
  unpinned=$(jq -r '.mcpServers[]?.args[]? // empty' .mcp.json 2>/dev/null | grep -E '@latest' || true)
  if [ -z "$unpinned" ]; then
    add_result "no @latest MCP pins" "pass" ""
  else
    add_result "no @latest MCP pins" "fail" "found: $unpinned"
  fi
fi

# Swarm templates
if [ -f .swarms/templates/handoff.yaml ]; then
  if grep -q 'tdd_state' .swarms/templates/handoff.yaml 2>/dev/null; then
    add_result "handoff.yaml has tdd_state" "pass" ""
  else
    add_result "handoff.yaml has tdd_state" "fail" "missing tdd_state block"
  fi
fi

# ─── Memory-plane health (memory-system review §7.6: failures must be loud) ──

# M-01a — Metabolism liveness probe (advisory). The dream/instinct/witness spawns
# call `claude -p --bare`; the 2026-07 audit found all three dead. This probe
# MIRRORS THE REAL SPAWN FORM (--bare is mandatory — a non-bare probe authenticates
# via OAuth and false-greens the metabolism, hiding the exact bug M-01b fixes).
# Two independent failure modes are checked: (1) --bare auth ("Not logged in"),
# (2) a portable `timeout` (absent on stock macOS → pre-compact-witness dies).
# Skipped in CI (no interactive OAuth session) via HARNESS_DOCTOR_SKIP_SPAWN=1.
if [ "${HARNESS_DOCTOR_SKIP_SPAWN:-0}" != "1" ] && command -v claude >/dev/null 2>&1; then
  # JUSTIFIED: 2>&1 capture — we inspect stdout/stderr for the auth marker and need the exit code
  probe_out=$(claude -p --bare 'reply with the single word ok' 2>&1); probe_rc=$?
  if printf '%s' "$probe_out" | grep -qi 'not logged in'; then
    add_result "metabolism: --bare spawn authenticates" "warn" "claude -p --bare → 'Not logged in' (rc=$probe_rc). The dream/instinct/witness spawns are DEAD. M-01b fix: drop --bare so OAuth is read (staged patch). --bare cannot read OAuth by design."
  elif [ "$probe_rc" -ne 0 ]; then
    add_result "metabolism: --bare spawn authenticates" "warn" "claude -p --bare exited $probe_rc (non-auth failure) — investigate before trusting the metabolism"
  else
    add_result "metabolism: --bare spawn authenticates" "pass" "claude -p --bare returned rc=0 (unexpected — --bare normally refuses OAuth; verify this is a real auth, not an echo)"
  fi
else
  add_result "metabolism: --bare spawn authenticates" "warn" "spawn probe skipped (HARNESS_DOCTOR_SKIP_SPAWN=1 or claude not on PATH) — cannot confirm liveness"
fi
# Portable timeout — pre-compact-witness.sh:68 uses `timeout 120`; macOS lacks it.
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
  add_result "metabolism: portable timeout available" "pass" "$(command -v timeout gtimeout 2>/dev/null | head -1)"
else
  add_result "metabolism: portable timeout available" "warn" "no timeout/gtimeout on PATH — pre-compact-witness.sh:68 dies 'command not found' before claude runs (M-01b adds a portable guard)"
fi

# Witness briefs stuck in "(pending)" — the async witness died without anyone noticing
stuck_witness=$(find .claude/memory/.cache/checkpoints -name '*.md' -mtime +2 -exec grep -l '(pending)' {} \; 2>/dev/null | head -3 || true)
if [ -z "$stuck_witness" ]; then
  add_result "no witness briefs stuck pending >2d" "pass" ""
else
  add_result "no witness briefs stuck pending >2d" "fail" "async witness died: $(echo "$stuck_witness" | tr '\n' ' ')"
fi

# Initiative pointers — session-end.sh reads these for token attribution
if [ -s .claude/state/current-initiative ] && [ -s .claude/state/current-spec ]; then
  add_result "initiative/spec pointers present" "pass" ""
else
  add_result "initiative/spec pointers present" "fail" "run: bash .claude/scripts/initiative-state.sh sync"
fi

# Initiative STATE.md freshness (the always-current state answer; 7d budget)
state_md=$(ls -t initiatives/active/*.STATE.md 2>/dev/null | head -1 || true)
if [ -n "$state_md" ]; then
  state_age_d=$(( ( $(date +%s) - $(stat -f %m "$state_md" 2>/dev/null || stat -c %Y "$state_md" 2>/dev/null || echo 0) ) / 86400 ))
  if [ "$state_age_d" -le 7 ]; then
    add_result "initiative STATE.md fresh (≤7d)" "pass" "${state_age_d}d old"
  else
    add_result "initiative STATE.md fresh (≤7d)" "fail" "${state_age_d}d old — run initiative-state.sh sync"
  fi
else
  add_result "initiative STATE.md fresh (≤7d)" "fail" "no STATE.md — run: bash .claude/scripts/initiative-state.sh sync"
fi

# Index lifecycle population — unknown-status entries can't promote or decay
if [ -s .claude/memory/index.jsonl ] && command -v jq >/dev/null 2>&1; then
  idx_total=$(wc -l < .claude/memory/index.jsonl | tr -d ' ')
  idx_unknown=$(jq -rs '[.[] | select(.status == "unknown" or .status == null)] | length' .claude/memory/index.jsonl 2>/dev/null || echo 0)
  if [ "$idx_total" -gt 0 ] && [ $(( idx_unknown * 2 )) -le "$idx_total" ]; then
    add_result "memory index lifecycle ≥50% populated" "pass" "$((idx_total - idx_unknown))/$idx_total"
  else
    add_result "memory index lifecycle ≥50% populated" "fail" "$idx_unknown/$idx_total unknown — backfill frontmatter + rebuild"
  fi
fi

# Skill-use telemetry (gap-audit G17) — never-used skills + adherence signal
if [ -s .claude/hooks/.log/skill-use.jsonl ]; then
  used=$(jq -r '.skill' .claude/hooks/.log/skill-use.jsonl 2>/dev/null | sort -u | wc -l | tr -d ' ')
  total_sk=$(find .claude/skills -name 'SKILL.md' -type f 2>/dev/null | wc -l | tr -d ' ')
  add_result "skill-use telemetry" "pass" "$used of $total_sk skills invoked at least once (log: .claude/hooks/.log/skill-use.jsonl)"
else
  add_result "skill-use telemetry" "warn" "no skill-use.jsonl yet — skill-use-log.sh hook records Skill invocations once installed"
fi

# Cache hit-rate (gap-audit G1) — warn when measured and below threshold
CACHE_HIT_MIN="${CACHE_HIT_MIN:-40}"
summary=.claude/hooks/.log/cost-summary.json
if [ -f "$summary" ]; then
  age_s=$(( $(date +%s) - $(stat -f %m "$summary" 2>/dev/null || stat -c %Y "$summary" 2>/dev/null || echo 0) ))
  hr=$(jq -r '.cache_hit_rate // -1' "$summary" 2>/dev/null || echo -1)
  hr_int=${hr%.*}; hr_int=${hr_int:-0}
  if [ "$age_s" -gt 86400 ] || [ "$hr_int" -lt 0 ]; then
    add_result "cache hit-rate measured" "pass" "no fresh data — run cost-report.sh to refresh"
  elif [ "$hr_int" -lt "$CACHE_HIT_MIN" ]; then
    add_result "cache hit-rate ≥${CACHE_HIT_MIN}%" "warn" "${hr}% — prefix churn? check CLAUDE.md/agents/skill-frontmatter stability (§IX)"
  else
    add_result "cache hit-rate ≥${CACHE_HIT_MIN}%" "pass" "${hr}%"
  fi
else
  add_result "cache hit-rate measured" "pass" "no cost-summary.json yet — run cost-report.sh"
fi

# Stop-verify bypass surface (gap-audit G48) — blocks logged in the last 7 days
blog=.claude/state/stop-verify-blocks.log
if [ -s "$blog" ]; then
  week_ago=$(date -v-7d -Iseconds 2>/dev/null || date -d '7 days ago' -Iseconds 2>/dev/null)
  recent_blocks=$(awk -F'\t' -v c="$week_ago" 'BEGIN{n=0} $1 >= c {n++} END{print n}' "$blog" 2>/dev/null || echo 0)
  if [ "${recent_blocks:-0}" -gt 0 ]; then
    add_result "stop-verify blocks (7d)" "warn" "$recent_blocks block(s) in the last week — each was either fixed or bypassed by resubmission; review $blog"
  else
    add_result "stop-verify blocks (7d)" "pass" "none recent"
  fi
else
  add_result "stop-verify blocks (7d)" "pass" "no block log yet"
fi

# Feedback intake wiring (gap-audit G60) — connectors ship with empty-default
# env expansion (${KEY:-}), so a "configured" source can still be dead. Check
# the actual env keys; say UNWIRED instead of letting intake look operational.
if [ -f .claude/routines/feedback-poll.yml ]; then
  fb_servers=$(jq -r '.mcpServers | keys[]' .mcp.json 2>/dev/null | grep -iE 'fireflies|intercom|pendo|slack' || true)
  if [ -z "$fb_servers" ]; then
    add_result "feedback intake wiring" "warn" "feedback-poll.yml exists but no feedback-source MCP (fireflies/intercom/pendo/slack) in .mcp.json — copy a catalogue block from _disabled_examples (docs/ADOPTION.md)"
  else
    wired=0
    for s in $fb_servers; do
      # env var names referenced as ${VAR:-} in the server's env block
      vars=$(jq -r --arg s "$s" '.mcpServers[$s].env // {} | to_entries[].value' .mcp.json 2>/dev/null | grep -oE '[A-Z][A-Z0-9_]+' || true)
      for v in $vars; do
        [ -n "$(eval "printf '%s' \"\${$v:-}\"")" ] && wired=$((wired + 1))
      done
    done
    if [ "$wired" -eq 0 ]; then
      add_result "feedback intake wiring" "warn" "feedback-source MCPs present but every auth env key is EMPTY — intake is configured but UNWIRED; export the API keys (docs/ADOPTION.md §feedback)"
    else
      add_result "feedback intake wiring" "pass" "$wired feedback-source credential(s) set"
    fi
  fi
fi

# Anti-slop ramp expiry (gap-audit G50) — advisory pass must flip to gating after 30 days
wirein=.claude/state/anti-slop-wirein.date
if [ -f "$wirein" ] && [ -f .github/workflows/pr-review.yml ]; then
  wd=$(head -1 "$wirein" | tr -d ' ')
  cutoff30=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d 2>/dev/null)
  if [ -n "$wd" ] && [ "$wd" \< "$cutoff30" ]; then
    if grep -q 'continue-on-error: true' .github/workflows/pr-review.yml; then
      add_result "anti-slop ramp (30d)" "warn" "wired in $wd (>30d ago) but pr-review.yml is still advisory — remove continue-on-error to make it gating, and add the job to the ruleset"
    else
      add_result "anti-slop ramp (30d)" "pass" "ramp complete; pass is gating"
    fi
  else
    add_result "anti-slop ramp (30d)" "pass" "within 30-day calibration window (since $wd)"
  fi
else
  add_result "anti-slop ramp (30d)" "warn" "no .claude/state/anti-slop-wirein.date — ramp clock unrecorded (gap-audit G50)"
fi

# ─── Stale swarm worktrees (e2e-audit swarm-4) ──────────────────────────
# A worktree whose fleet entry reached a terminal status (merged/reverted/
# crashed/blocked) should have been torn down — the graveyard wedges redispatch
# and eats disk. verified-merge now removes them; this catches the leftovers.
if [ -f .swarms/coordinator/fleet.json ] && command -v jq >/dev/null 2>&1; then
  stale_wts=""
  # JUSTIFIED: jq muted — a malformed fleet.json yields no entries; the [swarm] category already validates its schema
  while IFS='	' read -r s wt; do
    [ -n "$s" ] && [ -n "$wt" ] && [ -d "$wt" ] && stale_wts="$stale_wts $s"
  done < <(jq -r '.fleet | to_entries[] | select(.value.status == "merged" or .value.status == "reverted" or .value.status == "crashed" or .value.status == "blocked") | "\(.key)\t\(.value.worktree // "")"' .swarms/coordinator/fleet.json 2>/dev/null)
  if [ -n "$stale_wts" ]; then
    add_result "stale swarm worktrees" "warn" "terminal-status streams still have worktrees:${stale_wts} — remove with: git worktree remove --force .claude/worktrees/<id>"
  else
    add_result "stale swarm worktrees" "pass" "no terminal-status stream retains a worktree"
  fi
fi

# ─── Live ruleset drift (e2e-audit ci-gates-2) ────────────────────────
# The ruleset FILE is inert until applied server-side. Fetch live rulesets and
# assert (a) a main-targeting active ruleset exists, (b) its required-check
# contexts are a superset of the file's. Warn-only when gh/network unavailable.
if command -v gh >/dev/null 2>&1 && [ -f .github/rulesets/main-protection.json ]; then
  # JUSTIFIED: gh failure (no auth/remote/network) yields empty — handled as a warn, not a crash
  live_rulesets=$(gh api "repos/{owner}/{repo}/rulesets" 2>/dev/null || true)
  if [ -z "$live_rulesets" ] || [ "$live_rulesets" = "[]" ]; then
    add_result "live branch ruleset" "warn" "no server-side ruleset found (or gh unauthenticated) — every required check is ADVISORY; apply: gh api repos/{owner}/{repo}/rulesets --method POST --input .github/rulesets/main-protection.json"
  else
    # JUSTIFIED: jq muted on unexpected API shapes — empty live id falls into the warn branch
    live_id=$(printf '%s' "$live_rulesets" | jq -r '[.[] | select(.target=="branch" and .enforcement=="active")][0].id // empty' 2>/dev/null)
    if [ -z "$live_id" ]; then
      add_result "live branch ruleset" "warn" "rulesets exist but none is an ACTIVE branch ruleset — protection is off"
    else
      # JUSTIFIED: jq/gh muted — an unreadable detail response degrades to a drift warn below
      live_ctx=$(gh api "repos/{owner}/{repo}/rulesets/$live_id" 2>/dev/null | jq -r '.rules[]? | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null | sort)
      file_ctx=$(jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' .github/rulesets/main-protection.json 2>/dev/null | sort)
      missing_ctx=$(comm -23 <(printf '%s\n' "$file_ctx") <(printf '%s\n' "$live_ctx") | tr '\n' ' ')
      if [ -n "${missing_ctx// /}" ]; then
        add_result "live branch ruleset" "fail" "live ruleset is missing required contexts from the file: ${missing_ctx} — re-apply main-protection.json"
      else
        add_result "live branch ruleset" "pass" "active branch ruleset covers all file contexts"
      fi
    fi
  fi
else
  add_result "live branch ruleset" "warn" "gh unavailable — cannot verify server-side protection"
fi

# ─── Routine installation coverage (e2e-audit docs-truth-3) ─────────────
# Routines are authored YAML but install NOTHING by themselves. Enumerate them
# against the install record so the unattended layer (GC, OQ aging, circuit
# breaker, Sentry poll) can't silently never fire.
if ls .claude/routines/*.yml >/dev/null 2>&1; then
  routines_rec=".claude/state/routines-installed"
  missing_routines=""
  for ry in .claude/routines/*.yml; do
    rname=$(awk '/^name:/{print $2; exit}' "$ry")
    [ -z "$rname" ] && rname=$(basename "$ry" .yml)
    case "$rname" in
      overnight-build) rkey="overnight-build-backstop" ;;  # local backstop name differs
      *) rkey="$rname" ;;
    esac
    # JUSTIFIED: a missing record file means nothing installed — every routine lands in the missing list
    grep -qx "$rkey" "$routines_rec" 2>/dev/null || missing_routines="${missing_routines}${rname} "
  done
  if [ -z "$missing_routines" ]; then
    add_result "routine installs" "pass" "every .claude/routines/*.yml has an install record"
  else
    add_result "routine installs" "warn" "routines with NO install record: ${missing_routines}— locally-eligible ones: bash .claude/scripts/install-overnight-tasks.sh; cloud-only (overnight-build, feedback-*): claude.ai/code/routines (Routine Installation Matrix: docs/AUTOPILOT.md)"
  fi
fi

# ─── Oversized runtime logs (e2e-audit failure-recovery-5) ──────────────
# gc-logs.sh rotates these (session-end backstop + gc-nightly routine), but if
# neither has fired, multi-night runs grow unbounded — warn before disk pressure.
# JUSTIFIED: find over dirs that may not exist yet — empty result is the pass case
big_logs=$(find .claude/hooks/.log .claude/memory/.cache .swarms -type f \( -name '*.log' -o -name '*.jsonl' \) -size +52428800c 2>/dev/null | head -5 | tr '\n' ' ')
if [ -n "${big_logs// /}" ]; then
  add_result "runtime log size" "warn" "oversized (>50MB) runtime logs: ${big_logs}— run: bash .claude/scripts/gc-logs.sh (rotation backstop also fires at session end)"
else
  add_result "runtime log size" "pass" "no runtime log over the 50MB rotation cap"
fi

# ─── Release-please authority (e2e-audit release-deploy-6) ──────────────
# A placeholder package-name means the single tag/changelog authority is
# broken-by-default: release PRs reference a package that doesn't exist.
if [ -f release-please-config.json ]; then
  if grep -q '@your-org/your-repo' release-please-config.json; then
    add_result "release-please config" "warn" "release-please-config.json still has the placeholder package-name '@your-org/your-repo' — releases are broken until set (setup.sh configures it by stack)"
  elif [ ! -f .release-please-manifest.json ]; then
    add_result "release-please config" "warn" ".release-please-manifest.json missing — release-please v4 needs the manifest to track versions; seed it (setup.sh does)"
  else
    add_result "release-please config" "pass" "config customized + manifest present (single tag authority)"
  fi
fi

# ─── Anthropic credential secret (e2e-audit ci-gates-4) ─────────────────
# claude-review/claude-security are gating required checks — a missing
# credential fails every PR with an opaque SDK error. Either secret works:
# CLAUDE_CODE_OAUTH_TOKEN (subscription, 'claude setup-token') or
# ANTHROPIC_API_KEY (metered API).
if command -v gh >/dev/null 2>&1; then
  # JUSTIFIED: gh failure (no auth/remote) yields empty list — handled as the warn branch, not a crash
  _secrets="$(gh secret list 2>/dev/null || true)"
  if echo "$_secrets" | grep -qE '^CLAUDE_CODE_OAUTH_TOKEN'; then
    add_result "Anthropic credential secret" "pass" "CLAUDE_CODE_OAUTH_TOKEN present (subscription — no metered spend)"
  elif echo "$_secrets" | grep -qE '^ANTHROPIC_API_KEY'; then
    # OAuth-everywhere (T-153): gate satisfied but metered. Nudge to the free token.
    add_result "Anthropic credential secret" "warn" "only ANTHROPIC_API_KEY (metered) set — LLM CI bills per call; prefer the free subscription token: gh secret set CLAUDE_CODE_OAUTH_TOKEN (claude setup-token), then gh secret delete ANTHROPIC_API_KEY"
  else
    add_result "Anthropic credential secret" "warn" "no credential secret (or gh unauthenticated) — claude-review/claude-security required checks will fail every PR; set the FREE token: gh secret set CLAUDE_CODE_OAUTH_TOKEN (claude setup-token)"
  fi
fi

# ─── Deploy stub wiring (e2e-audit release-deploy-1) ────────────────────
# canary-deploy.yml ships as a STUB (echo + sleep). Unwired is fine (warn) —
# but DEPLOY_WIRED=true while the STUB marker is still present means someone
# armed the gate around placeholder steps: that's a fail.
if [ -f .github/workflows/canary-deploy.yml ]; then
  if grep -q '^# STUB' .github/workflows/canary-deploy.yml; then
    # JUSTIFIED: gh failure/absent variable yields empty — treated as unwired (the safe default)
    wired_var=$(gh variable get DEPLOY_WIRED 2>/dev/null || true)
    if [ "$wired_var" = "true" ]; then
      add_result "deploy stub" "fail" "DEPLOY_WIRED=true but canary-deploy.yml still carries the STUB marker — the gate is armed around echo+sleep placeholders; wire the platform first (docs/DEPLOY-INTEGRATION.md), then remove the marker"
    else
      add_result "deploy stub" "warn" "canary-deploy.yml is a STUB and DEPLOY_WIRED is unset — deploys are BYO and refuse to run (by design); wire via docs/DEPLOY-INTEGRATION.md"
    fi
  else
    add_result "deploy stub" "pass" "canary-deploy.yml has no STUB marker (platform wired)"
  fi
fi

printf ']\n' >> "$result_file"

if [ "$JSON_MODE" -eq 1 ]; then
  cat "$result_file"
else
  # JUSTIFIED: jq over the result file — a missing/unparseable file yields count 0, which the >0 gate below treats as "no failures recorded"; the 2>/dev/null hides only the jq parse noise
  fail_count=$(jq '[.[] | select(.status=="fail")] | length' "$result_file" 2>/dev/null || echo 0)
  total=$(jq 'length' "$result_file" 2>/dev/null || echo 0)
  printf '\n%s check(s), %s failure(s)\n' "$total" "$fail_count"
  [ "${fail_count:-0}" -gt 0 ] && exit 1
fi
