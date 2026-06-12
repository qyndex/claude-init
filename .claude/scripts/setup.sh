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
# e2e-audit greenfield-5: jq is load-bearing for every security hook (they now
# fail CLOSED without it, blocking all Bash/Write) — a warn here strands the
# operator in an unusable harness. Hard fail like git.
command -v jq  >/dev/null || fail "jq not installed — REQUIRED (hooks fail closed without it). brew install jq / apt install jq"
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

step "Greenfield template-clean (e2e-audit greenfield-1)"
# The factory's OWN dev state rides along in the cp: 100+ completed harness
# tasks, specs/plans 001-003, harness ADRs, an initiative STATE file. In a new
# project that makes verify.sh red-on-arrival and seeds the loop with foreign
# work. Move it all to docs/factory-history/ (auditable, out of the live path).
# Guarded: NEVER runs inside the factory repo itself (its CI exercises that
# state), and TEMPLATE_CLEAN=0 skips explicitly.
# JUSTIFIED: git config muted — no remote configured means not the factory clone, which is the cleaning case
origin_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
if [ "${TEMPLATE_CLEAN:-1}" = "1" ] && ! printf '%s' "$origin_url" | grep -q "claude-init"; then
  hist="docs/factory-history"
  cleaned=0
  # 1. TASKS.md → header/format sections only; factory task lines archived.
  if [ -f tasks/TASKS.md ] && grep -qE '^- \[.\] T-[0-9]+.*spec:00[1-3]' tasks/TASKS.md; then
    mkdir -p "$hist"
    cp tasks/TASKS.md "$hist/TASKS.factory.md"
    awk '
      /^## Active$/ {print; print ""; print "<!-- queue cleaned by setup.sh template-clean — factory tasks archived in docs/factory-history/ -->"; act=1; next}
      act && /^## / {print ""; print; next}
      act {next}
      {print}' \
      "$hist/TASKS.factory.md" > tasks/TASKS.md
    cleaned=$((cleaned+1))
  fi
  # 2. Factory specs/plans (001-003 harness work) → history.
  for f in specs/active/001-*.md specs/active/002-*.md specs/active/003-*.md \
           plans/active/001-*.md plans/active/002-*.md plans/active/003-*.md; do
    [ -f "$f" ] || continue
    mkdir -p "$hist/$(dirname "$f")"
    mv "$f" "$hist/$f"
    cleaned=$((cleaned+1))
  done
  # 3. Memory: keep the taxonomy + 0000 templates; archive factory ADRs/incidents.
  for f in .claude/memory/decisions/000[1-9]-*.md .claude/memory/incidents/2026-*.md; do
    [ -f "$f" ] || continue
    mkdir -p "$hist/$(dirname "$f")"
    mv "$f" "$hist/$f"
    cleaned=$((cleaned+1))
  done
  # 4. Initiative STATE files are factory-run artifacts.
  for f in initiatives/active/*.STATE.md; do
    [ -f "$f" ] || continue
    mkdir -p "$hist/initiatives"
    mv "$f" "$hist/initiatives/"
    cleaned=$((cleaned+1))
  done
  # 5. Factory runtime state (live-e2e FINDING-2): hook logs, memory cache, and
  # session state read as THIS project's history by harness-doctor. Personal
  # settings are deleted outright (never belong to a new project); the rest is
  # archived. Keeps state scaffolding: .gitkeep, adopt/, skill-triggers.tsv.
  rm -f .claude/settings.local.json
  for d in .claude/hooks/.log .claude/memory/.cache; do
    [ -d "$d" ] || continue
    [ -n "$(find "$d" -type f -print -quit 2>/dev/null)" ] || continue
    mkdir -p "$hist/$d"
    cp -R "$d"/. "$hist/$d/" 2>/dev/null
    find "$d" -mindepth 1 -delete 2>/dev/null
    cleaned=$((cleaned+1))
  done
  if [ -d .claude/state ]; then
    state_purged=0
    for f in .claude/state/* .claude/state/.[!.]*; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in .gitkeep|adopt|skill-triggers.tsv) continue ;; esac
      mkdir -p "$hist/.claude/state"
      cp -R "$f" "$hist/.claude/state/" 2>/dev/null
      rm -rf "$f"
      state_purged=1
    done
    [ "$state_purged" = 1 ] && cleaned=$((cleaned+1))
  fi
  if [ "$cleaned" -gt 0 ]; then
    ok "template-clean: $cleaned factory artifact group(s) moved to $hist/"
  else
    ok "template-clean: no factory dev state found (already clean)"
  fi
else
  ok "template-clean skipped (factory repo or TEMPLATE_CLEAN=0)"
fi

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
mkdir -p .claude/state/adopt
touch .claude/hooks/.log/.gitkeep
# Seed the coordinator runtime-state files. They are gitignored (never shipped via
# clone/copy) but validate.sh REQUIRES them — so a fresh install must create them or
# the [swarm] check fails. Idempotent: only written when absent.
if [ ! -f .swarms/coordinator/fleet.json ]; then
  cat > .swarms/coordinator/fleet.json <<'EOF'
{
  "_doc": "Coordinator's view of the fleet. Updated as streams spawn/complete/fail. Read by /swarm-status command.",
  "_schema_version": 1,
  "last_updated": null,
  "fleet": {}
}
EOF
fi
if [ ! -f .swarms/coordinator/decisions.log ]; then
  cat > .swarms/coordinator/decisions.log <<'EOF'
# Coordinator Decision Log

Append-only. One line per decision. Format:

```
<ISO-8601 timestamp> | <stream-id> | <decision> | <rationale>
```
EOF
fi
ok "runtime directories ready"

step "Activating the characterization gate (greenfield: empty manifest)"
# verify.sh's characterization gate reads .claude/state/adopt/uncharacterized-paths.txt.
# On greenfield there is no legacy to protect, but the file must EXIST (empty, header
# only) so the gate is wired and active — a brownfield /adopt run later fills it with
# real globs. Absent file = gate silently inert; empty file = gate active, nothing flagged. (AC-15)
char_manifest=.claude/state/adopt/uncharacterized-paths.txt
if [ ! -f "$char_manifest" ]; then
  cat > "$char_manifest" <<'EOF'
# uncharacterized-paths.txt — legacy-safety manifest for the characterization gate.
#
# Each non-comment line is a glob marking a source zone that has NO characterization
# test yet; verify.sh BLOCKS edits to files matching these globs until one exists.
# Greenfield starts EMPTY (nothing to protect). A brownfield `/adopt start` run
# populates this with the repo's source roots; you remove a glob once its zone is
# characterized. See docs/ADOPTION.md and .claude/skills/characterize/SKILL.md.
EOF
  ok "characterization manifest created (empty — gate active, nothing flagged)"
else
  ok "characterization manifest already present"
fi

# Defensive bootstrap of the loop-control state file (consecutive-aborts.json).
# loop-state.sh self-heals a missing file, but seeding it here means the schema-
# validated state exists from install and the harness-validate CI step has
# something to check. (T-036)
aborts_state=.claude/state/consecutive-aborts.json
if [ ! -f "$aborts_state" ]; then
  cat > "$aborts_state" <<EOF
{
  "count": 0,
  "same_task_streak": 0,
  "last_task": null,
  "last_error_hash": null,
  "last_pivot_attempt": 0,
  "updated": "$(date -Iseconds)"
}
EOF
  ok "seeded loop-control state (consecutive-aborts.json)"
else
  ok "loop-control state already present"
fi

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
ensure_ignore ".swarms/events/"
ensure_ignore ".claude/sessions/"
# e2e-audit greenfield-2: do NOT ignore all of verify/ — evidence-gate requires
# the lightweight trail (REPORT.md, AC screenshots, red/green ledger) in the PR
# diff. Ignore only the heavy artifacts, exactly like the factory .gitignore.
ensure_ignore "verify/**/*.webm"
ensure_ignore "verify/**/*.zip"
ensure_ignore "verify/**/network.har"
ensure_ignore "verify/**/html-report/"
ensure_ignore "verify/**/test-results/"
ensure_ignore "verify/.skip-log"
ensure_ignore "!verify/**/red.log"
ensure_ignore "!verify/**/green.log"
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

step "Evidence rig bootstrap (web stacks)"
# e2e-audit e2e-rig-4c: on web-stack detection install the standalone Playwright
# evidence rig so the verify chain can actually run journeys. Best-effort —
# a failed browser download must not abort setup; the verifier re-runs it.
if [ -f package.json ]; then
  # JUSTIFIED: rig bootstrap failure degrades to a warn — verifier.md step 2 re-runs it pre-first-journey
  bash .claude/scripts/rig-bootstrap.sh || warn "rig-bootstrap failed — run 'bash .claude/scripts/rig-bootstrap.sh' manually before the first /verify"
else
  note "no package.json — browser rig skipped (stack-runner AC proof applies; see collect-evidence.sh)"
fi

step "Priming the daily-batch gate"
# merge-gate.yml blocks PRs until a daily-batch.yml run has passed within its window.
# On a fresh install there is no prior run, so the very first PR would be blocked for
# a day. Kick off one daily-batch run now so the first PR after setup can pass. Guarded:
# only when gh is authenticated AND an origin remote exists (a real GitHub repo). (AC-14)
if command -v gh >/dev/null 2>&1 \
   && gh auth status >/dev/null 2>&1 \
   && git remote get-url origin >/dev/null 2>&1; then
  if gh workflow run daily-batch.yml >/dev/null 2>&1; then
    ok "dispatched an initial daily-batch.yml run (first PR won't be gate-blocked)"
  else
    # JUSTIFIED: the workflow may not be on the default branch yet on a brand-new repo; a failed dispatch is non-fatal — the operator can re-run after first push
    warn "could not dispatch daily-batch.yml yet (push to the default branch first, then: gh workflow run daily-batch.yml)"
  fi
else
  note "skip daily-batch priming — no authenticated gh + origin remote yet."
  note "  After your first push, run:  gh workflow run daily-batch.yml   (unblocks the first PR's merge-gate)"
fi

step "Initial validation"
# e2e-audit greenfield-6: capture the exit instead of letting set -e abort here —
# a validation hiccup must not strand the install with the plugin layer (the
# constitution's superpowers dependency) silently missing. Failures are reported
# now, the remaining steps run, and the script exits non-zero at the END.
validate_rc=0
bash .claude/scripts/validate.sh || validate_rc=$?
if [ "$validate_rc" -ne 0 ]; then
  warn "initial validation FAILED (rc=$validate_rc) — continuing with the remaining setup steps; fix the categories above and re-run setup.sh (idempotent). Setup will exit non-zero at the end."
fi

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

step "Branch protection ruleset (e2e-audit ci-gates-2)"
# The ruleset file means NOTHING until applied server-side — every required
# check is advisory until then. Offer to apply when gh is authenticated;
# record the decision either way so harness-doctor can nag about it.
mkdir -p .claude/state
ruleset_state=".claude/state/ruleset-applied"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && git config --get remote.origin.url >/dev/null 2>&1; then
  apply_ruleset="${APPLY_RULESET:-}"
  if [ -z "$apply_ruleset" ] && [ -t 0 ]; then
    printf "  Apply .github/rulesets/main-protection.json to this repo now? [y/N] "
    read -r reply
    case "$reply" in y|Y|yes) apply_ruleset=1 ;; *) apply_ruleset=0 ;; esac
  fi
  if [ "$apply_ruleset" = "1" ]; then
    if gh api "repos/{owner}/{repo}/rulesets" --method POST --input .github/rulesets/main-protection.json >/dev/null 2>&1; then
      printf '%s\tapplied\n' "$(date -Iseconds)" > "$ruleset_state"
      ok "ruleset applied server-side"
    else
      printf '%s\tapply-failed\n' "$(date -Iseconds)" > "$ruleset_state"
      warn "ruleset apply FAILED (need repo admin; CI check names must exist) — re-run: gh api repos/{owner}/{repo}/rulesets --method POST --input .github/rulesets/main-protection.json"
    fi
  else
    printf '%s\tdeclined\n' "$(date -Iseconds)" > "$ruleset_state"
    warn "ruleset NOT applied — branch protection is INACTIVE until you run: gh api repos/{owner}/{repo}/rulesets --method POST --input .github/rulesets/main-protection.json"
  fi
else
  printf '%s\tno-gh-auth\n' "$(date -Iseconds)" > "$ruleset_state"
  warn "gh not authenticated / no remote — ruleset NOT applied (harness-doctor will keep flagging this)"
fi

step "Release-please config (e2e-audit release-deploy-6)"
# release-please is the SINGLE tag/changelog authority. The factory config ships
# with a placeholder package-name + node release-type — set both by detected
# stack, or warn loudly so a broken-by-default workflow never goes unnoticed.
if [ -f release-please-config.json ] && command -v jq >/dev/null 2>&1; then
  if grep -q '@your-org/your-repo' release-please-config.json; then
    rp_type=""
    [ -f package.json ] && rp_type="node"
    [ -z "$rp_type" ] && [ -f pyproject.toml ] && rp_type="python"
    [ -z "$rp_type" ] && [ -f Cargo.toml ] && rp_type="rust"
    [ -z "$rp_type" ] && [ -f go.mod ] && rp_type="go"
    if [ -n "$rp_type" ]; then
      rp_name="$(basename "$(pwd)")"
      if [ -f package.json ]; then
        # JUSTIFIED: package.json name read; a missing/invalid name keeps the directory-name fallback
        pj_name="$(jq -r '.name // empty' package.json 2>/dev/null || true)"
        [ -n "$pj_name" ] && rp_name="$pj_name"
      fi
      tmp="release-please-config.json.tmp.$$"
      jq --arg t "$rp_type" --arg n "$rp_name" \
        '."release-type"=$t | .packages."."."release-type"=$t | .packages."."."package-name"=$n' \
        release-please-config.json > "$tmp" && mv "$tmp" release-please-config.json
      ok "release-please configured: release-type=$rp_type package-name=$rp_name"
    else
      warn "release-please-config.json still has the PLACEHOLDER package-name and no stack was detected — releases will NOT work until you edit it (release-type + package-name)"
    fi
  else
    ok "release-please-config.json already customized"
  fi
  [ -f .release-please-manifest.json ] || { printf '{\n  ".": "0.1.0"\n}\n' > .release-please-manifest.json; ok "seeded .release-please-manifest.json at 0.1.0"; }
fi

step "Anthropic credential preflight (e2e-audit ci-gates-4)"
# claude-review / claude-security are GATING required checks — without a
# credential they fail on every PR with an opaque SDK error. Catch it at setup.
# Either secret satisfies the gate: CLAUDE_CODE_OAUTH_TOKEN (Pro/Max
# subscription via 'claude setup-token') or ANTHROPIC_API_KEY (metered API).
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && git config --get remote.origin.url >/dev/null 2>&1; then
  if gh secret list 2>/dev/null | grep -qE '^(ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN)'; then
    ok "Anthropic credential secret present (ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN)"
  else
    warn "No Anthropic credential secret — claude-review/claude-security (required checks) will fail every PR. Set one: gh secret set CLAUDE_CODE_OAUTH_TOKEN (from 'claude setup-token') or gh secret set ANTHROPIC_API_KEY"
  fi
else
  note "gh unavailable — cannot verify Anthropic credential secret (harness-doctor re-checks)"
fi

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

# Final gate (greenfield-6): re-run validation now that plugins/templates are in
# place — and surface the earlier failure as THE exit code so CI/operators see it.
if [ "$validate_rc" -ne 0 ]; then
  step "Final validation (re-run after remaining steps)"
  validate_rc=0
  bash .claude/scripts/validate.sh || validate_rc=$?
  if [ "$validate_rc" -ne 0 ]; then
    warn "setup completed WITH validation failures (rc=$validate_rc) — fix the categories above and re-run bash .claude/scripts/setup.sh"
    exit "$validate_rc"
  fi
  ok "final validation clean — the initial failure was transient (resolved by later steps)"
fi
