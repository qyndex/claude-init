#!/usr/bin/env bash
# Validates the .claude/ harness configuration. Run after edits.
#
# Data-driven: discovers files via find/glob rather than hardcoded lists.
# Adding a new agent / skill / hook / command is automatically validated.
# Removing one is automatically forgotten (no false-positive failures).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

fails=0
warns=0
fail() { printf '  ✗ %s\n' "$*"; fails=$((fails+1)); }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ⚠ %s\n' "$*"; warns=$((warns+1)); }
note() { printf '  ℹ %s\n' "$*"; }

echo "→ Validating .claude/ harness"
echo

# ─── 1. Core configuration files MUST exist ─────────────────────────────
echo "[core]"
core_required=(
  ".claude/CLAUDE.md"
  ".claude/settings.json"
  ".mcp.json"
  ".claude/VERSION"
)
for f in "${core_required[@]}"; do
  if [ -f "$f" ]; then ok "$f"; else fail "$f missing"; fi
done
echo

# ─── 2. JSON validation (every .json file) ──────────────────────────────
echo "[json]"
if command -v jq >/dev/null; then
  json_count=0
  while IFS= read -r -d '' f; do
    json_count=$((json_count+1))
    if jq -e . "$f" >/dev/null 2>&1; then
      :  # silent ok — too many to list
    else
      fail "invalid JSON: $f"
    fi
    # JUSTIFIED: find -print0 feed — 2>/dev/null hides "no such directory" for any absent path arg; absent paths contribute no JSON files to validate
  done < <(find .claude .github .swarms .mcp.json -name '*.json' -type f -not -path '*/.cache/*' -print0 2>/dev/null)
  ok "validated $json_count JSON files"
else
  warn "jq not installed — JSON files not validated"
fi
echo

# ─── 3. YAML frontmatter (every .md with leading ---) ──────────────────
echo "[frontmatter]"
has_yaml=0
if command -v python3 >/dev/null; then
  # JUSTIFIED: capability probe for the yaml module — non-zero/import error just means "not available", handled by the elif + regex fallback
  if python3 -c "import yaml" 2>/dev/null; then
    has_yaml=1
  # JUSTIFIED: optional pyyaml bootstrap — 2>/dev/null on both halves; failure just means we fall through to the regex fallback (warned later), not an error
  elif python3 -m pip install --quiet --user pyyaml 2>/dev/null && python3 -c "import yaml" 2>/dev/null; then
    has_yaml=1
  fi
fi

fm_count=0
fm_bad=0
while IFS= read -r -d '' f; do
  # JUSTIFIED: head probe for a leading frontmatter fence — 2>/dev/null guards a file that vanished mid-walk; no fence means skip, the intended path
  if head -1 "$f" 2>/dev/null | grep -q '^---$'; then
    fm_count=$((fm_count+1))
    fm=$(awk '/^---$/{c++; next} c==1{print}' "$f")

    if [ "$has_yaml" = "1" ]; then
      # JUSTIFIED: 2>/dev/null hides the python traceback on a malformed block; the non-zero exit is what we act on (the "bad YAML" fail below)
      if ! echo "$fm" | python3 -c "import sys, yaml; yaml.safe_load(sys.stdin.read())" 2>/dev/null; then
        fail "bad YAML frontmatter: $f"
        fm_bad=$((fm_bad+1))
        continue
      fi
    fi

    # Required fields differ by file kind
    case "$f" in
      .claude/commands/*)
        # Commands need `description:`
        if ! echo "$fm" | grep -qE '^description:[[:space:]]*\S'; then
          fail "command missing description: $f"
          fm_bad=$((fm_bad+1))
        fi
        ;;
      .claude/agents/*)
        # Agents need name + description + model + permissionMode
        for key in name description model permissionMode; do
          if ! echo "$fm" | grep -qE "^${key}:[[:space:]]*\S"; then
            fail "agent $f missing frontmatter key: $key"
            fm_bad=$((fm_bad+1))
          fi
        done
        ;;
      .claude/skills/*/SKILL.md)
        # Skills need name + description
        for key in name description; do
          if ! echo "$fm" | grep -qE "^${key}:[[:space:]]*\S"; then
            fail "skill $f missing frontmatter key: $key"
            fm_bad=$((fm_bad+1))
          fi
        done
        ;;
      .claude/memory/*/0000-template.md|specs/templates/*|plans/templates/*|initiatives/templates/*|.claude/templates/*|.claude/rules/*)
        # Templates + path-scoped rules: lenient — they're scaffolds, not invocable units
        :
        ;;
      *)
        # Generic: at least name and description
        if ! echo "$fm" | grep -qE '^name:[[:space:]]*\S' || ! echo "$fm" | grep -qE '^description:[[:space:]]*\S'; then
          warn "frontmatter missing name+description: $f"
        fi
        ;;
    esac
  fi
# JUSTIFIED: find -print0 feed — 2>/dev/null hides "no such directory" for any absent template dir; absent dirs contribute no files to validate
done < <(find .claude specs/templates plans/templates initiatives/templates -name '*.md' -type f -print0 2>/dev/null)

if [ "$has_yaml" = "0" ]; then
  warn "python3+pyyaml not available — used regex fallback for YAML"
fi
ok "validated $fm_count frontmatter blocks ($fm_bad bad)"
echo

# ─── 4. Executable shell files ──────────────────────────────────────────
echo "[executables]"
while IFS= read -r -d '' f; do
  if [ -f "$f" ]; then
    case "$f" in
      */lib/*)
        : ;;  # sourced libraries (scripts/lib/*.sh) are `.`-sourced, not executed — exec bit optional
      *)
        if [ -x "$f" ]; then
          :  # silent ok
        else
          fail "not executable: $f"
        fi
        ;;
    esac
  fi
# JUSTIFIED: find -print0 feed — 2>/dev/null hides "no such directory" for any absent dir; an absent dir simply contributes no files to check
done < <(find .claude/hooks .claude/statuslines .claude/scripts -name '*.sh' -type f -print0 2>/dev/null)
# JUSTIFIED: find|wc count — 2>/dev/null hides "no such directory"; absent dirs contribute 0 to the reported shell-file count
sh_count=$(find .claude/hooks .claude/statuslines .claude/scripts -name '*.sh' -type f 2>/dev/null | wc -l | tr -d ' ')
ok "$sh_count shell files checked"
echo

# ─── 5. Agents must be in expected dirs ─────────────────────────────────
echo "[agents]"
# JUSTIFIED: find|wc count — 2>/dev/null hides "no such directory"; a missing dir yields 0, which the next line reports as "too few agents"
agent_count=$(find .claude/agents -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$agent_count" -lt 5 ]; then
  fail "only $agent_count agents found — expected at least 5"
else
  ok "$agent_count agents discovered"
fi

# Core agents that ARE required by name (the workflow won't function without these)
for core_agent in architect planner implementer reviewer verifier; do
  # JUSTIFIED: find presence probe — 2>/dev/null hides "no such directory"; an empty result correctly triggers the "core agent missing" fail
  if find .claude/agents -name "${core_agent}.md" -type f 2>/dev/null | grep -q .; then
    :  # silent
  else
    fail "core agent missing: $core_agent"
  fi
done
echo

# ─── 6. Skills directory ────────────────────────────────────────────────
echo "[skills]"
# JUSTIFIED: find|wc count — 2>/dev/null hides "no such directory"; a repo without skills yields 0, reported as informational
skill_count=$(find .claude/skills -name 'SKILL.md' -type f 2>/dev/null | wc -l | tr -d ' ')
ok "$skill_count project-specific skills"
note "(plugin-installed skills validated by \`/plugin list\`, not here)"
echo

# ─── 7. Commands directory ──────────────────────────────────────────────
echo "[commands]"
# JUSTIFIED: find|wc count — 2>/dev/null hides "no such directory"; a repo without commands yields 0, reported as informational
cmd_count=$(find .claude/commands -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
ok "$cmd_count commands discovered"
echo

# ─── 8. Hooks: every referenced hook must exist ─────────────────────────
echo "[hooks]"
# Pull hook references from settings.json — if it references one, it must exist
if [ -f .claude/settings.json ] && command -v jq >/dev/null; then
  # Extract every "command" path that ends in .sh
  # JUSTIFIED: jq read of settings.json — 2>/dev/null drops the duplicate parse error already reported by [json]; the in-query // empty handles missing keys
  referenced_hooks=$(jq -r '..|.command? // empty | select(type=="string")' .claude/settings.json 2>/dev/null \
    | grep -oE '\.claude/hooks/[a-zA-Z0-9_-]+\.sh' | sort -u)
  for hook_path in $referenced_hooks; do
    if [ -f "$hook_path" ]; then
      :
    else
      fail "settings.json references missing hook: $hook_path"
    fi
  done
  hook_count=$(echo "$referenced_hooks" | wc -l | tr -d ' ')
  ok "$hook_count referenced hooks present"
fi

# Also: every hook on disk should appear in settings.json (otherwise dead code)
# JUSTIFIED: find probe — 2>/dev/null hides "no such directory" so a repo without hooks yields an empty list instead of an error
on_disk=$(find .claude/hooks -name '*.sh' -type f 2>/dev/null | sort)
for h in $on_disk; do
  hname=$(basename "$h")
  # JUSTIFIED: grep -q presence probe — 2>/dev/null hides "no such file" on a fresh repo; absence then correctly warns the hook is unreferenced
  if ! grep -q "$hname" .claude/settings.json 2>/dev/null; then
    warn "hook on disk but not referenced in settings.json: $hname"
  fi
done
echo

# ─── 9. Autopilot artifacts ─────────────────────────────────────────────
echo "[autopilot]"
autopilot_required=(
  ".claude/routines/overnight-build.yml"
  ".claude/routines/dream-cron.yml"
  ".claude/routines/quarterly-archive.yml"
  ".claude/templates/overnight-report.md"
  "docs/AUTOPILOT.md"
  "docs/PARALLEL-SWARM.md"
)
for f in "${autopilot_required[@]}"; do
  if [ -f "$f" ]; then ok "$(basename $f)"; else fail "missing $f"; fi
done
echo

# ─── 10. Swarm state ────────────────────────────────────────────────────
echo "[swarm]"
swarm_required=(
  ".swarms/coordinator/fleet.json"
  ".swarms/coordinator/decisions.log"
  ".swarms/templates/brief.md"
  ".swarms/templates/analysis.md"
  ".swarms/templates/task.json"
)
for f in "${swarm_required[@]}"; do
  if [ -f "$f" ]; then ok "$(basename $f)"; else fail "missing $f"; fi
done

# Swarm commands
for c in plan dispatch status merge stop respawn; do
  if [ -f ".claude/commands/swarm/${c}.md" ]; then
    :  # silent
  else
    fail "/swarm:$c missing"
  fi
done
echo

# ─── 11. Spec/plan/task scaffold ────────────────────────────────────────
echo "[scaffold]"
scaffold_required=(
  "specs/templates/spec.md"
  "plans/templates/plan.md"
  "initiatives/templates/initiative.md"
  "tasks/TASKS.md"
  "OKRs.md"
  "roadmap.md"
  "slo.yml"
)
for f in "${scaffold_required[@]}"; do
  if [ -f "$f" ]; then ok "$(basename $f)"; else fail "missing $f"; fi
done

# Round 10 A: accept: must be a test command, not echo/true/:
if [ -f tasks/TASKS.md ]; then
  bad_accept=0
  while IFS= read -r accept_line; do
    cmd=$(echo "$accept_line" | sed 's/.*accept:[[:space:]]*//')
    # Skip placeholder/tbd
    case "$cmd" in
      *"<"*|*tbd*|*human*|"") continue ;;
    esac
    # Must invoke a recognized test runner / verification
    if ! echo "$cmd" | grep -qE 'pytest|vitest|jest|npm test|pnpm test|yarn test|bun test|cargo test|go test|playwright|verify\.sh|coverage|tdd-ledger'; then
      # Reject obvious no-ops
      if echo "$cmd" | grep -qE '^(echo|true|:|exit 0)'; then
        warn "task accept: is a no-op, not a test: \"$cmd\""
        bad_accept=$((bad_accept+1))
      fi
    fi
    # JUSTIFIED: grep over TASKS.md — 2>/dev/null swallows the "no such file" case; a missing/empty file yields zero loop iterations, the intended no-op
  done < <(grep -E '^\s*accept:' tasks/TASKS.md 2>/dev/null)
  [ "$bad_accept" -eq 0 ] && ok "all task accept: commands look like real verifications"
fi
echo

# ─── 12. Memory layout ──────────────────────────────────────────────────
echo "[memory]"
memory_required=(
  ".claude/memory/MEMORY.md"
  ".claude/memory/decisions/0000-template.md"
  ".claude/memory/patterns/0000-template.md"
  ".claude/memory/deprecations/REGISTRY.md"
)
for f in "${memory_required[@]}"; do
  if [ -f "$f" ]; then ok "$(basename $f)"; else fail "missing $f"; fi
done

# Memory budget enforcement
if [ -f .claude/memory/MEMORY.md ]; then
  # JUSTIFIED: wc on a file guarded by the enclosing [ -f ]; `|| echo 0` is a belt-and-braces default so the -gt comparison never sees an empty string
  mem_lines=$(wc -l < .claude/memory/MEMORY.md 2>/dev/null || echo 0)
  if [ "$mem_lines" -gt 200 ]; then
    warn "MEMORY.md is $mem_lines lines (cap=200) — run \`.claude/scripts/memory-gc.sh enforce\`"
  else
    ok "MEMORY.md within budget ($mem_lines/200 lines)"
  fi
fi
echo

# ─── 13. Settings security invariants ───────────────────────────────────
echo "[security]"
if command -v jq >/dev/null && [ -f .claude/settings.json ]; then
  # disableBypassPermissionsMode must be "disable" (string, not bool); lives under .permissions
  # JUSTIFIED: jq has a // "unset" fallback in-query, so 2>/dev/null only drops the duplicate stderr on a malformed file already flagged by [json]
  bypass=$(jq -r '.permissions.disableBypassPermissionsMode // .disableBypassPermissionsMode // "unset"' .claude/settings.json 2>/dev/null)
  if [ "$bypass" = "disable" ]; then
    ok "disableBypassPermissionsMode: disable"
  else
    fail "disableBypassPermissionsMode should be \"disable\", got: $bypass"
  fi

  # No `Bash(env)` in allow
  # JUSTIFIED: jq read of settings.json — 2>/dev/null hides parse errors already surfaced by the [json] section; grep -q drives the check
  if jq -r '.permissions.allow[]?' .claude/settings.json 2>/dev/null | grep -qE '^Bash\(env(\s|\)|:)'; then
    fail "Bash(env) is in allow list — env exfil risk"
  else
    ok "no Bash(env) in allow"
  fi

  # No bare Bash(claude:*)
  # JUSTIFIED: jq read of settings.json — 2>/dev/null hides parse errors that the [json] section already reports; grep -q drives the check
  if jq -r '.permissions.allow[]?' .claude/settings.json 2>/dev/null | grep -qE '^Bash\(claude:\*\)$'; then
    fail "Bash(claude:*) catch-all in allow — should enumerate subcommands"
  else
    ok "no Bash(claude:*) catch-all"
  fi
fi
echo

# ─── 14. MCP version pinning ────────────────────────────────────────────
echo "[mcp]"
if [ -f .mcp.json ] && command -v jq >/dev/null; then
  # JUSTIFIED: jq on .mcp.json — suppress parse noise; `|| true` keeps an empty grep result from tripping pipefail (no matching pin is the normal case)
  pkgs=$(jq -r '.mcpServers[]?.args[]? // empty' .mcp.json 2>/dev/null | grep -oE '@[a-zA-Z0-9_/.-]+@[a-zA-Z0-9.-]+' || true)
  # JUSTIFIED: jq read; `|| true` because grep exits 1 when there are no @latest pins, which is the desired (clean) outcome
  unpinned=$(jq -r '.mcpServers[]?.args[]? // empty' .mcp.json 2>/dev/null | grep -E '@latest' || true)
  if [ -n "$unpinned" ]; then
    warn "MCP packages pinned to @latest (supply-chain risk):"
    echo "$unpinned" | sed 's/^/    /'
  else
    ok "no @latest pins in .mcp.json"
  fi
fi
echo

# ─── Summary ────────────────────────────────────────────────────────────
echo "─────────────────────────────────────"
if [ "$fails" -gt 0 ]; then
  printf '✗ %d failures, %d warnings\n' "$fails" "$warns"
  exit 1
elif [ "$warns" -gt 0 ]; then
  printf '✓ all checks passed (with %d warnings)\n' "$warns"
else
  printf '✓ all checks passed cleanly\n'
fi
