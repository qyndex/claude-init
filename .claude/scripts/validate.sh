#!/usr/bin/env bash
# Validates the .claude/ harness configuration. Run after edits.
#
# Data-driven: discovers files via find/glob rather than hardcoded lists.
# Adding a new agent / skill / hook / command is automatically validated.
# Removing one is automatically forgotten (no false-positive failures).

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

# ─── Spec 001 AC-21: --json structured report ───────────────────────────
# Back-compat is absolute: default (no-flag) mode is byte-for-byte unchanged.
# --json re-runs the SAME checks via the text path, then parses the human
# output (category headers + ✓/✗/⚠ lines) into a structured report. Parsing
# the text output — rather than instrumenting every ok/fail/warn call site —
# keeps the 350-line body untouched and the two modes provably in lock-step.
if [ "${1:-}" = "--json" ]; then
  self="$ROOT/.claude/scripts/validate.sh"
  # JUSTIFIED: 2>/dev/null drops the text run's stderr — we parse only stdout into JSON; the real exit status is captured in text_rc and re-raised below
  text_out="$(bash "$self" 2>/dev/null)"; text_rc=$?
  # JUSTIFIED: 2>/dev/null on the GNU date probe — the `||` fallback to a POSIX UTC format handles BSD date, so a failure here is expected and recovered, not silent
  gen_at="$(date -Iseconds 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Pre-translate the UTF-8 status glyphs (✓ ✗ ⚠) into ASCII sentinels with a
  # byte-wise sed (LC_ALL=C) so BSD awk never has to decode multibyte input —
  # then parse the ASCII tags. This sidesteps "multibyte conversion failure"
  # on locales where awk would otherwise choke on the glyphs.
  printf '%s\n' "$text_out" \
    | LC_ALL=C sed -e 's/^  ✓ /@OK@/' -e 's/^  ✗ /@FAIL@/' -e 's/^  ⚠ /@WARN@/' \
    | LC_ALL=C awk -v gen_at="$gen_at" '
    function flush() {
      if (cat == "") return
      printf "%s{\"name\":%s,\"status\":%s,\"checked\":%d,\"failures\":[%s],\"warnings\":[%s]}",
             (started ? "," : ""), q(cat), q(status()), checked, fjoin, wjoin
      started = 1
    }
    function status() { return (nfail > 0 ? "fail" : (nwarn > 0 ? "warn" : "pass")) }
    function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
    function additem(arr, val) { return (arr == "" ? q(val) : arr "," q(val)) }
    BEGIN { print "{\"schema_version\":1,\"generated_at\":" q(gen_at) ",\"categories\":["
            cat=""; started=0 }
    /^\[.*\]$/ {
      flush()
      cat = substr($0, 2, length($0) - 2)
      checked = 0; nfail = 0; nwarn = 0; fjoin = ""; wjoin = ""
      next
    }
    /^@OK@/   { if (cat != "") checked++ ; tpass++ ; next }
    /^@FAIL@/ { if (cat != "") { nfail++; fjoin = additem(fjoin, substr($0, 7)) } ; tfail++ ; next }
    /^@WARN@/ { if (cat != "") { nwarn++; wjoin = additem(wjoin, substr($0, 7)) } ; twarn++ ; next }
    END {
      flush()
      overall = (tfail > 0 ? "fail" : (twarn > 0 ? "warn" : "pass"))
      printf "],\"summary\":{\"passed\":%d,\"warned\":%d,\"failed\":%d,\"overall\":%s}}\n",
             tpass, twarn, tfail, "\"" overall "\""
    }
  '
  exit "$text_rc"
fi

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
  # e2e-audit hooks-engineering-4: security hooks fail closed without jq, so a
  # jq-less environment is a broken harness, not a degraded one.
  fail "jq not installed — JSON files not validated AND security hooks fail closed (install jq)"
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
# .claude/worktrees is gitignored runtime state (native worktrees) — never validated
done < <(find .claude specs/templates plans/templates initiatives/templates \
  -path '.claude/worktrees' -prune -o -name '*.md' -type f -print0 2>/dev/null)

if [ "$has_yaml" = "0" ]; then
  warn "python3+pyyaml not available — used regex fallback for YAML"
fi
ok "validated $fm_count frontmatter blocks ($fm_bad bad)"
echo

# ─── 3b. ADR single-schema (M-10) ───────────────────────────────────────
# Frontmatter `status:`/`supersedes` is the SOLE home for ADR status. The old
# body bullets (`- **Status**:`, `- **Supersedes**:`, `- **superseded_by**:`)
# duplicated it and drifted; reject them so the split can't reappear.
echo "[adr-single-schema]"
adr_schema_bad=0
while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in 0000-template.md|README.md) continue ;; esac
  if grep -qE '^- \*\*Status\*\*:|^- \*\*Supersedes\*\*:|^- \*\*superseded_by\*\*:' "$f"; then
    fail "ADR body-bullet status/supersedes (use frontmatter only — M-10): $f"
    adr_schema_bad=$((adr_schema_bad + 1))
  fi
# JUSTIFIED: find -print0 feed — 2>/dev/null hides an absent decisions/ dir (valid in a fresh repo); no ADRs means nothing to check
done < <(find .claude/memory/decisions -name '*.md' -type f -print0 2>/dev/null)
ok "ADR single-schema: $adr_schema_bad body-bullet violation(s)"
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

# Gap-audit G34: an agent whose contract claims it writes under .claude/memory/
# must actually hold a write-capable tool — otherwise the claim is mechanically
# impossible and the artifact silently never exists.
while IFS= read -r -d '' af; do
  if grep -qE '(written to|logged in) `\.claude/memory' "$af"; then
    tools_line=$(grep -m1 -E '^tools:' "$af" || echo "")
    if ! printf '%s' "$tools_line" | grep -qE 'Write|Edit'; then
      warn "agent claims memory writes but has no Write/Edit tool: $af (route the content through the NEXUS handoff instead)"
    fi
  fi
done < <(find .claude/agents -name '*.md' -type f -print0 2>/dev/null)

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

# Gap-audit G19: description frontmatter must fit the maxSkillDescriptionChars
# cap (settings.json, default 1536) — oversized descriptions are silently
# truncated by Claude Code, breaking trigger phrases.
desc_cap=$(jq -r '.maxSkillDescriptionChars // 1536' .claude/settings.json 2>/dev/null || echo 1536)
desc_over=0
while IFS= read -r -d '' sf; do
  dlen=$(awk '/^description:/{sub(/^description:[[:space:]]*/,""); print length($0); exit}' "$sf")
  if [ "${dlen:-0}" -gt "$desc_cap" ]; then
    warn "skill description exceeds ${desc_cap}-char cap ($dlen): $sf"
    desc_over=$((desc_over+1))
  fi
done < <(find .claude/skills -name 'SKILL.md' -type f -print0 2>/dev/null)
[ "$desc_over" -eq 0 ] && ok "all skill descriptions within ${desc_cap}-char cap"

# Gap-audit G8: every `.claude/skills/<name>` path referenced from the docs
# must resolve to a real skill directory — dangling references send readers
# (and the model) to dead ends.
dangling=0
while IFS= read -r ref; do
  name="${ref#.claude/skills/}"
  case "$name" in .archive|"") continue ;; esac
  if [ ! -d ".claude/skills/$name" ]; then
    warn "dangling skill reference: $ref (no such directory)"
    dangling=$((dangling+1))
  fi
  # JUSTIFIED: grep -rhoE across docs — 2>/dev/null mutes unreadable-file noise; no matches is a valid (clean) outcome via the empty while-loop
done < <(grep -rhoE '\.claude/skills/[a-z0-9][a-z0-9_-]*' CLAUDE.md README.md docs/*.md .claude/skills/*/SKILL.md 2>/dev/null | sort -u)
[ "$dangling" -eq 0 ] && ok "all referenced skill paths resolve"

# Gap-audit G16: REGISTRY.md must track the catalogue (row count == SKILL.md count)
if [ -f .claude/skills/REGISTRY.md ]; then
  reg_rows=$(grep -c '^| `' .claude/skills/REGISTRY.md || true)
  if [ "${reg_rows:-0}" -eq "$skill_count" ]; then
    ok "REGISTRY.md fresh ($reg_rows/$skill_count skills)"
  else
    warn "REGISTRY.md stale ($reg_rows rows vs $skill_count skills) — run .claude/scripts/regen-skill-registry.sh"
  fi
else
  warn "no .claude/skills/REGISTRY.md — run .claude/scripts/regen-skill-registry.sh"
fi

# Gap-audit G19: skill-creator contract — when_to_use should be present (warn)
wtu_missing=0
while IFS= read -r -d '' sf; do
  if ! grep -qE '^when_to_use:[[:space:]]*\S' "$sf"; then
    wtu_missing=$((wtu_missing+1))
  fi
done < <(find .claude/skills -name 'SKILL.md' -type f -print0 2>/dev/null)
if [ "$wtu_missing" -eq 0 ]; then
  ok "all skills carry when_to_use frontmatter"
else
  warn "$wtu_missing skill(s) missing when_to_use frontmatter (router/trigger coverage suffers)"
fi
echo

# ─── 7. Commands directory ──────────────────────────────────────────────
echo "[commands]"
# JUSTIFIED: find|wc count — 2>/dev/null hides "no such directory"; a repo without commands yields 0, reported as informational
cmd_count=$(find .claude/commands -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
ok "$cmd_count commands discovered"

# Gap-audit G22: commands are user-only by contract (README: every command
# carries disable-model-invocation: true). Enforce it so a new command can't
# silently become model-invocable.
dmi_missing=0
while IFS= read -r -d '' cf; do
  case "$cf" in */README.md) continue ;; esac
  if ! grep -qE '^disable-model-invocation:[[:space:]]*true' "$cf"; then
    fail "command missing disable-model-invocation: true — $cf (user-only contract, commands/README.md)"
    dmi_missing=$((dmi_missing+1))
  fi
done < <(find .claude/commands -name '*.md' -type f -print0 2>/dev/null)
[ "$dmi_missing" -eq 0 ] && ok "all commands carry disable-model-invocation: true"

# Gap-audit G21: every backticked /command a hook injects must resolve to a
# real command, skill, or known built-in — dangling refs advertise dead ends.
builtin_cmds="compact clear rewind config plugin loop fast context fewer-permission-prompts"
dangling_cmd=0
while IFS= read -r ref; do
  name="${ref#\`/}"
  [ -z "$name" ] && continue
  if [ -f ".claude/commands/${name}.md" ] || [ -d ".claude/skills/${name}" ]; then continue; fi
  case " $builtin_cmds " in *" $name "*) continue ;; esac
  warn "hook injects dangling slash-command: /$name (no command/skill/built-in resolves)"
  dangling_cmd=$((dangling_cmd+1))
done < <(grep -rhoE '`/[a-z][a-z0-9-]+' .claude/hooks/*.sh 2>/dev/null | sort -u)
[ "$dangling_cmd" -eq 0 ] && ok "all hook-injected slash-commands resolve"
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

# Gap-audit G6: matcher coverage — a hook whose code branches on
# tool_name == Agent/Task is dead code unless it is registered under a
# PreToolUse matcher that can actually deliver those tools (being registered
# "somewhere", e.g. only under Bash, silently disables the branch).
for h in $on_disk; do
  hname=$(basename "$h")
  if grep -qE 'tool_name"?\s*=\s*"(Agent|Task)"' "$h" 2>/dev/null; then
    covered=$(jq -r --arg cmd "$hname" '
      .hooks.PreToolUse[]? | select([.hooks[]?.command] | any(contains($cmd)))
      | .matcher // ""' .claude/settings.json 2>/dev/null | grep -c 'Agent' || true)
    if [ "${covered:-0}" -eq 0 ]; then
      fail "$hname branches on tool_name Agent/Task but is not registered under an Agent|Task matcher (dead code — gap-audit G6)"
    else
      ok "$hname covered by an Agent-matching matcher"
    fi
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
# FINDING-19 (live-e2e 2026-06-13): coordinator runtime-state files are
# gitignored MUTABLE state (.gitignore: .swarms/coordinator/fleet.json,
# workflow-state.json) — correct, they shouldn't be versioned. But a fresh CI
# checkout therefore lacks them, so a hard "missing" fail made the [swarm]
# category (and harness-validate) fail on EVERY clean checkout, including
# claude-init's own. Seed the runtime files to their documented empty shape if
# absent, then check — self-heals deterministically without versioning state.
# JUSTIFIED: seed is best-effort — the swarm_required loop below re-checks each
# file with -f and emits a real `fail` if seeding didn't produce it, so a failed
# mkdir/write is surfaced there, never silently swallowed by these || true guards.
mkdir -p .swarms/coordinator 2>/dev/null || true
if [ ! -f .swarms/coordinator/fleet.json ]; then
  # JUSTIFIED: heredoc redirect is best-effort; the -f re-check in swarm_required
  # below emits a real `fail` if the file still doesn't exist, so a write failure
  # is surfaced there, not hidden by this 2>/dev/null || true.
  cat > .swarms/coordinator/fleet.json 2>/dev/null <<'FLEET_JSON' || true
{
  "_doc": "Coordinator's view of the fleet. Updated as streams spawn/complete/fail. Read by /swarm-status command.",
  "_schema_version": 1,
  "last_updated": null,
  "fleet": {}
}
FLEET_JSON
fi
if [ ! -f .swarms/coordinator/decisions.log ]; then
  # JUSTIFIED: write failure is caught by the -f re-check in swarm_required below
  printf '%s\n' '# Coordinator Decision Log' '' 'Append-only. One line per decision.' \
    > .swarms/coordinator/decisions.log 2>/dev/null || true
fi
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

# Round 10 A + e2e-audit spec-pipeline-3/tdd-loop-5: task-line grammar + accept
# discipline. Required pipe fields on every task line; backtick-free accept;
# no-op accepts are a FAIL on actionable ([ ]/[~]) implementer-owned tasks
# (history stays warn-only — done markers can't be rewritten without forging).
if [ -f tasks/TASKS.md ]; then
  bad_accept=0
  grammar_bad=0
  # One awk pass emits: status \x1f line \x1f owner \x1f accept  per task block
  while IFS=$'\x1f' read -r t_status t_line t_owner t_accept; do
    # Grammar: required pipe fields (priority/created joined the canon — the
    # tasks skill and planner format blocks must produce them)
    for field in 'spec:' 'phase:' 'priority:' 'created:' 'est:'; do
      if ! printf '%s' "$t_line" | grep -q "$field"; then
        fail "task line missing required field '$field': ${t_line:0:60}"
        grammar_bad=$((grammar_bad+1))
      fi
    done
    # Taxonomy enum: warn on ACTIONABLE tasks only — [x]/[s] history predates the
    # taxonomy ("critical") and can't be rewritten without forging the ledger
    case "$t_status" in
      x|s) : ;;
      *)
        if ! printf '%s' "$t_line" | grep -qE 'priority: *(hotfix|incident-followup|security|P1-spec|debt|normal|cleanup|deprecation)( |\||$)'; then
          warn "task priority outside the taxonomy: ${t_line:0:60}"
        fi ;;
    esac
    # Accept discipline
    cmd="$t_accept"
    case "$cmd" in
      *'`'*)
        fail "task accept: contains backticks — must be a plain executable command: \"$cmd\""
        bad_accept=$((bad_accept+1)); continue ;;
      *"<"*|*tbd*|*human*|"") continue ;;  # placeholder / operator-resolved
    esac
    is_noop=0
    # No-ops: classic (echo/true/:/exit 0), neutered (trailing || true), and
    # existence-only probes with no content assertion (bare ls / lone test -f)
    if printf '%s' "$cmd" | grep -qE '^(echo|true$|: *$|exit 0)'; then is_noop=1; fi
    if printf '%s' "$cmd" | grep -qE '\|\| *true *$'; then is_noop=1; fi
    if printf '%s' "$cmd" | grep -qE '^(ls |test -[a-z] [^&|;]*$)'; then is_noop=1; fi
    if [ "$is_noop" = 1 ]; then
      if { [ "$t_status" = " " ] || [ "$t_status" = "~" ]; } && printf '%s' "$t_owner" | grep -qi 'implementer'; then
        fail "actionable implementer task has a no-op accept: \"$cmd\""
      else
        warn "task accept: is a no-op, not a test: \"$cmd\""
      fi
      bad_accept=$((bad_accept+1))
    fi
  done < <(awk '
    function flush() { if (line != "") printf "%s\x1f%s\x1f%s\x1f%s\n", status, line, owner, accept; line = "" }
    /^- \[.\] T-[0-9]+/ {
      flush()
      status = substr($0, 4, 1); line = $0; owner = ""; accept = ""
      next
    }
    /^- \[/ || /^#/ { flush(); next }
    line != "" && /^[ \t]+owner:/  { o = $0; sub(/^[ \t]+owner:[ ]*/, "", o); owner = o }
    line != "" && /^[ \t]+accept:/ { a = $0; sub(/^[ \t]+accept:[ ]*/, "", a); accept = a }
    END { flush() }
  ' tasks/TASKS.md 2>/dev/null)
  [ "$bad_accept" -eq 0 ] && [ "$grammar_bad" -eq 0 ] && ok "task grammar + accept discipline clean ($(grep -cE '^- \[.\] T-[0-9]+' tasks/TASKS.md 2>/dev/null || echo 0) tasks)"
fi
echo

# ─── 11b. Live artifact lint (e2e-audit spec-pipeline-4/5) ───────────────
# Malformed specs/plans previously failed silent-open mid-run: no frontmatter
# check, no id↔filename check, no status enum, dangling plan→spec pointers,
# duplicate ids across active+archive, TASKS.md spec refs to nowhere.
echo "[artifacts]"
artifact_bad=0
fm_field() { # fm_field <file> <key> — first value of <key> inside the leading frontmatter block
  awk -v k="$2" 'NR==1 && $0 != "---" { exit } NR>1 && /^---$/ { exit } $0 ~ "^" k ":" { sub("^" k ":[ \t]*", ""); sub(/[ \t]+#.*$/, ""); gsub(/^"|"$/, ""); print; exit }' "$1"
}
for kind in specs plans; do
  enum='draft|review|approved|shipped|paused|dropped|superseded|abandoned'
  [ "$kind" = "plans" ] && enum='draft|review|approved|superseded'
  for f in "$kind"/active/*.md; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .md)
    if [ "$(head -1 "$f")" != "---" ]; then
      fail "$f: no leading frontmatter block"
      artifact_bad=$((artifact_bad+1)); continue
    fi
    fm_id=$(fm_field "$f" id)
    fm_status=$(fm_field "$f" status)
    # The filename must START with the frontmatter id followed by '-'. This accepts
    # BOTH the single-token scheme (001-todo-app → id 001) and multi-token ids
    # (R-052-gdpr → id R-052). A naive cut at the first '-' (${base%%-*}) wrongly
    # rejected real PREFIX-NNN id schemes (e.g. an R-NNN spec corpus, 173 false fails).
    if [ "$base" != "$fm_id" ] && [ "${base#"$fm_id"-}" = "$base" ]; then
      fail "$f: frontmatter id '$fm_id' is not the filename prefix (expected filename to start '$fm_id-')"
      artifact_bad=$((artifact_bad+1))
    fi
    if ! printf '%s' "$fm_status" | grep -qE "^($enum)$"; then
      fail "$f: status '$fm_status' not in enum ($enum)"
      artifact_bad=$((artifact_bad+1))
    fi
    if [ "$kind" = "plans" ]; then
      plan_spec=$(fm_field "$f" spec)
      if [ -z "$plan_spec" ] || [ ! -f "$plan_spec" ]; then
        fail "$f: spec pointer '$plan_spec' does not resolve"
        artifact_bad=$((artifact_bad+1))
      fi
    fi
  done
done
# ids globally unique across active ∪ archive (per kind)
for kind in specs plans; do
  # JUSTIFIED: missing archive dir yields no entries — uniqueness over active only
  dupes=$(ls "$kind"/active/*.md "$kind"/archive/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | grep -oE '^[0-9]+' | sort | uniq -d)
  if [ -n "$dupes" ]; then
    fail "$kind: duplicate ids across active+archive: $(echo $dupes | tr '\n' ' ')"
    artifact_bad=$((artifact_bad+1))
  fi
done
# every TASKS.md spec:NNN resolves (HOTFIX sentinel exempt)
if [ -f tasks/TASKS.md ]; then
  for sid in $(grep -oE '\| *spec:[A-Za-z0-9]+' tasks/TASKS.md | grep -oE '[A-Za-z0-9]+$' | sort -u); do
    case "$sid" in HOTFIX|NNN) continue ;; esac  # sentinels: hotfix + the Format template line
    # JUSTIFIED: glob probes — no match in EITHER dir means the ref dangles, which is exactly the failure below
    if ! ls specs/active/"$sid"-*.md >/dev/null 2>&1 && ! ls specs/archive/"$sid"-*.md >/dev/null 2>&1; then
      fail "tasks/TASKS.md references spec:$sid but no specs/{active,archive}/$sid-*.md exists"
      artifact_bad=$((artifact_bad+1))
    fi
  done
fi
[ "$artifact_bad" -eq 0 ] && ok "specs/plans frontmatter, ids, pointers, and TASKS.md spec refs all consistent"
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

# Gap-audit G39: plans without decisions = architecture happening with zero
# ADRs — the entire lifecycle (staleness, supersession, conflict detection)
# runs on an empty set. Real plans must produce real decisions.
plan_count=$(find plans/active -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')
adr_count=$(find .claude/memory/decisions -name '*.md' -type f -not -name '0000-template.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$plan_count" -gt 0 ] && [ "$adr_count" -eq 0 ]; then
  fail "plans/active has $plan_count plan(s) but .claude/memory/decisions/ holds only the template — create ADRs via .claude/scripts/adr-new.sh (gap-audit G39)"
else
  ok "ADR store non-vacuous ($adr_count ADR(s), $plan_count active plan(s))"
fi

# Lifecycle frontmatter — without status/created the promotion/decay rules in
# memory-promote.sh can never fire (memory-system review §7.4). Topic files
# (not templates, not the index page, not runtime briefs) must carry both.
fm_missing=0
fm_checked=0
while IFS= read -r -d '' f; do
  fm_checked=$((fm_checked+1))
  if ! grep -q '^status:' "$f" || ! grep -qE '^(created|written_at):' "$f"; then
    warn "memory file missing lifecycle frontmatter (status + created/written_at): $f"
    fm_missing=$((fm_missing+1))
  fi
  # JUSTIFIED: find 2>/dev/null mutes traversal noise on absent topic dirs — zero files is a valid (empty) memory tree
done < <(find .claude/memory/decisions .claude/memory/patterns .claude/memory/incidents .claude/memory/playbooks \
  -name '*.md' -not -name '0000-template.md' -type f -print0 2>/dev/null)
if [ "$fm_missing" -eq 0 ]; then
  ok "lifecycle frontmatter present on all $fm_checked topic files"
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

  # Gap-audit G3: cache/context env invariants §IX calls load-bearing
  ts=$(jq -r '.env.ENABLE_TOOL_SEARCH // "unset"' .claude/settings.json 2>/dev/null)
  if [ "$ts" = "true" ]; then
    ok "ENABLE_TOOL_SEARCH=true (MCP schemas deferred)"
  else
    fail "ENABLE_TOOL_SEARCH should be \"true\" in settings env, got: $ts (§IX cache invariant)"
  fi
  acw=$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW // "unset"' .claude/settings.json 2>/dev/null)
  if [ "$acw" != "unset" ] && [ -n "$acw" ]; then
    ok "CLAUDE_CODE_AUTO_COMPACT_WINDOW set ($acw)"
  else
    fail "CLAUDE_CODE_AUTO_COMPACT_WINDOW unset in settings env (§IX context invariant)"
  fi

  # e2e-audit security-automode-2: every ephemeral-exec verb allowed in
  # permissions must be covered by the dep-freshness hook's quick filter —
  # an allowed-but-unchecked `npx <pkg>` is an ungated download-and-run.
  eph_missing=0
  for verb in npx uvx bunx pnpx pipx; do
    if jq -r '.permissions.allow[]?' .claude/settings.json 2>/dev/null | grep -q "^Bash(${verb}[:)]"; then
      if grep -q "\"${verb} \"" .claude/hooks/pre-bash-dep-freshness.sh 2>/dev/null; then
        ok "ephemeral verb '${verb}' allowed AND handled by dep-freshness hook"
      else
        fail "ephemeral verb '${verb}' is in the allow list but NOT handled by pre-bash-dep-freshness.sh (security-automode-2)"
        eph_missing=1
      fi
    fi
  done

  # e2e-audit security-automode-1: every alwaysLoad MCP server with a write/exec
  # surface must have a PreToolUse matcher gating its write tools — otherwise MCP
  # writes bypass the constitution guard + secret scan entirely. git MCP has no
  # write-to-tree/push surface, so only filesystem + github are write-capable.
  if [ -f .mcp.json ]; then
    matchers=$(jq -r '[.hooks.PreToolUse[]?.matcher // empty] | join("\n")' .claude/settings.json 2>/dev/null)
    for srv in filesystem github; do
      always=$(jq -r --arg s "$srv" '.mcpServers[$s].alwaysLoad // false' .mcp.json 2>/dev/null)
      if [ "$always" = "true" ]; then
        if printf '%s\n' "$matchers" | grep -q "mcp__${srv}__"; then
          ok "alwaysLoad MCP '$srv' write tools have a PreToolUse matcher"
        else
          fail "alwaysLoad MCP '$srv' exposes write tools but no PreToolUse matcher gates mcp__${srv}__* (security-automode-1)"
        fi
      fi
    done
  fi
fi

# [force-bypass] — no script/workflow may set the constitution-bypass env var via export;
# that escape hatch is operator-shell-only and must never appear in harness automation.
# Pattern split across a variable so this validator file itself does not self-match.
_fb_pat='export[[:space:]]+FORCE_CONSTITUTION'"_EDIT"
# JUSTIFIED: grep exits 1 on no match (the desired clean outcome); `|| true` prevents pipefail triggering.
# Exclude runtime logs (.claude/hooks/.log/) — they capture transient command strings an operator
# may have typed, which are NOT committed harness automation and must not trip this invariant.
_fb_count=$(grep -rE "$_fb_pat" .claude .github 2>/dev/null | grep -v '\.claude/hooks/\.log/' | wc -l || true)
if [ "${_fb_count// /}" -eq 0 ]; then
  ok "no exported FORCE_CONSTITUTION_EDIT in harness files (force-bypass clean)"
else
  fail "found exported FORCE_CONSTITUTION_EDIT in harness files — escape hatch is operator-only"
fi

# Comment-triggered write workflows need an actor guard (e2e-audit ci-gates-5):
# a workflow that fires on issue/PR comments AND holds contents:write must gate
# its job on author_association, or any drive-by commenter can spin a runner.
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  grep -qE '^[[:space:]]*(issue_comment|pull_request_review_comment):' "$wf" || continue
  grep -qE '^[[:space:]]*contents:[[:space:]]*write' "$wf" || continue
  if grep -q 'author_association' "$wf"; then
    ok "comment-triggered write workflow has actor guard: $wf"
  else
    fail "comment-triggered workflow $wf holds contents:write but has NO author_association guard — drive-by comments can spin a privileged runner (ci-gates-5)"
  fi
done

# Docs must not teach the silently-ignored boolean form (e2e-audit docs-truth-2):
# Claude Code only honors the STRING "disable"; `true`/`false` are no-ops, so a
# doc recommending them gives operators a false sense of a lock being on or off.
# JUSTIFIED: grep exit 1 (no matches) is the desired clean state, not an abort
# docs/research/ is excluded: audit/research artifacts quote the bad patterns as findings.
_bool_bypass=$(grep -rnE 'disableBypassPermissionsMode[^a-zA-Z]*(true|false)' docs/ README.md 2>/dev/null | grep -v '^docs/research/' | grep -v 'silently ignore' || true)
if [ -z "$_bool_bypass" ]; then
  ok "docs never recommend boolean disableBypassPermissionsMode (only \"disable\" string works)"
else
  fail "docs recommend the boolean disableBypassPermissionsMode form, which Claude Code silently ignores: $(echo "$_bool_bypass" | head -2 | cut -d: -f1-2 | tr '\n' ' ')"
fi

# Task-legend drift guard (e2e-audit docs-truth-2): tasks/TASKS.md defines [s]
# as "skipped"; any doc glossing it as "shipped" teaches operators the wrong
# state machine (shipped is an issue-lifecycle stage, not a task marker).
# JUSTIFIED: grep exit 1 (no matches) is the desired clean state, not an abort
_s_drift=$(grep -rnE '\[s\][^a-zA-Z]*shipped' docs/ README.md 2>/dev/null | grep -v '^docs/research/' || true)
if [ -z "$_s_drift" ]; then
  ok "docs agree with tasks/TASKS.md legend: [s] = skipped, never shipped"
else
  fail "doc glosses [s] as 'shipped' but tasks/TASKS.md defines it as 'skipped': $(echo "$_s_drift" | head -2 | cut -d: -f1-2 | tr '\n' ' ')"
fi
echo

# ─── 14b. Constitution size cap (AC-37) ─────────────────────────────────
echo "[constitution-size]"
CONST_MAX_LINES="${CONST_MAX_LINES:-300}"
CONST_WARN_LINES="${CONST_WARN_LINES:-250}"
if [ -f .claude/CLAUDE.md ]; then
  const_lines=$(wc -l < .claude/CLAUDE.md | tr -d ' ')
  if [ "$const_lines" -gt "$CONST_MAX_LINES" ]; then
    fail "constitution .claude/CLAUDE.md is $const_lines lines (cap: $CONST_MAX_LINES). Run: /constitution-compact"
  elif [ "$const_lines" -gt "$CONST_WARN_LINES" ]; then
    warn "constitution .claude/CLAUDE.md is $const_lines lines (warn: $CONST_WARN_LINES). Consider: /constitution-compact"
  else
    ok "constitution .claude/CLAUDE.md is $const_lines lines / $CONST_MAX_LINES cap"
  fi
else
  warn "constitution .claude/CLAUDE.md not found"
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

# ─── 15. Ruleset ↔ job coverage (Spec 003 AC-14) ───────────────────────
# Root cause of the round-1 CI deadlock: a required_status_checks context with
# no matching PR-triggered job stays pending-forever and blocks every merge.
# For each required context, confirm a workflow has a job of that name AND the
# workflow triggers on pull_request with no paths: filter that could skip it.
echo "[ruleset-coverage]"
RULESET_FILE="${RULESET_FILE_OVERRIDE:-.github/rulesets/main-protection.json}"
if [ -f "$RULESET_FILE" ] && command -v jq >/dev/null; then
  # JUSTIFIED: jq read; `|| true` because an empty contexts list is a valid (if odd) ruleset and must not trip pipefail
  contexts=$(jq -r '.. | objects | .context? // empty' "$RULESET_FILE" 2>/dev/null | sort -u || true)
  if [ -z "$contexts" ]; then
    note "no required_status_checks contexts in $RULESET_FILE"
  else
    while IFS= read -r ctx; do
      [ -z "$ctx" ] && continue
      # Find a workflow file whose jobs map contains a job key == ctx.
      job_file=""
      for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
        [ -f "$wf" ] || continue
        # match a top-level job key "  <ctx>:" under the jobs: block (2-space indent convention)
        if grep -qE "^  ${ctx}:[[:space:]]*$" "$wf"; then job_file="$wf"; break; fi
      done
      if [ -z "$job_file" ]; then
        fail "required context '$ctx' maps to NO workflow job — PRs will hang pending-forever"
        continue
      fi
      # Confirm the workflow triggers on pull_request.
      if ! grep -qE '^[[:space:]]*pull_request:' "$job_file"; then
        fail "required context '$ctx' job in $job_file has no pull_request: trigger"
        continue
      fi
      # Warn ONLY if the pull_request trigger itself carries a paths: filter
      # (a paths: under a sibling push: trigger is fine — push isn't the gate).
      # Scan from the pull_request: line until the next same-or-shallower-indent
      # key (e.g. push:, permissions:, jobs:), and flag a paths: inside that block.
      if awk '
          /^[[:space:]]*pull_request:[[:space:]]*$/ { inpr=1; prind=match($0,/[^ ]/); next }
          inpr {
            ind=match($0,/[^ ]/)
            if ($0 ~ /^[[:space:]]*$/) next
            if (ind <= prind) { inpr=0; next }
            if ($0 ~ /^[[:space:]]+paths:/) { print "hit"; exit }
          }
        ' "$job_file" | grep -q hit; then
        warn "required context '$ctx' ($job_file) has a pull_request paths: filter — may stay pending on PRs that miss the filter"
      else
        ok "required context '$ctx' maps to $job_file (pull_request, no paths filter)"
      fi
    done <<< "$contexts"
  fi
else
  note "ruleset or jq unavailable — skipping ruleset-coverage check"
fi
echo

# ─── 15b. Handoff dialect (e2e-audit swarm-5) ───────────────────────────
# NEXUS handoffs are YAML (handoff-*.yaml, schema .swarms/templates/handoff.yaml).
# A consumer or template citing handoff-*.md re-splits the dialect — streams
# would write artifacts the coordinator can't parse.
echo "[handoff-dialect]"
# Targets SWARM handoffs only (.swarms/** paths or the handoff-*.md glob) — the
# session-handoff playbooks under .claude/memory/playbooks/ are a different,
# legitimately-markdown artifact class.
# JUSTIFIED: grep exit 1 = no offenders, the pass path
md_handoffs=$(grep -rln --exclude-dir=.log -e '\.swarms/[^ ]*handoff-[^ ]*\.md' -e 'handoff-\*\.md' -e 'handoff-<ts>\.md' .swarms/templates .claude/commands .claude/agents .claude/skills .claude/hooks docs/PARALLEL-SWARM.md 2>/dev/null || true)
if [ -n "$md_handoffs" ]; then
  for f in $md_handoffs; do
    fail "handoff-*.md reference (NEXUS dialect is .yaml): $f"
  done
else
  ok "no handoff-*.md references — single NEXUS yaml dialect"
fi
echo

# ─── 16. State-path producers (e2e-audit spec-pipeline-1) ───────────────
# A hook that reads .claude/state/<x> which nothing produces is a gate that can
# never fire (the /analyze marker was consumed by workflow-state.sh but produced
# by NOTHING). Every hook-referenced state path must map to a documented,
# existing producer in .claude/templates/state-registry.tsv.
echo "[state-producers]"
registry=.claude/templates/state-registry.tsv
if [ -f "$registry" ]; then
  # JUSTIFIED: grep across hooks — 2>/dev/null tolerates an empty hooks dir; no refs means the loop runs zero times
  state_refs=$(grep -hoE '\.claude/state/[A-Za-z0-9._-]+' .claude/hooks/*.sh 2>/dev/null | sed 's|\.claude/state/||' | sort -u)
  dangling=0
  for ref in $state_refs; do
    producer=$(awk -F'\t' -v r="$ref" '$0 !~ /^#/ && $1 == r {print $2; exit}' "$registry")
    if [ -z "$producer" ]; then
      fail "hook reads .claude/state/$ref but it has no documented producer (add to $registry)"
      dangling=$((dangling + 1))
    elif [ ! -f "$producer" ]; then
      fail "state path $ref: documented producer $producer does not exist"
      dangling=$((dangling + 1))
    fi
  done
  [ "$dangling" -eq 0 ] && ok "every hook-referenced state path has an existing documented producer"
else
  warn "no $registry — dangling-consumer check skipped"
fi
echo

# ─── 17. Model-doc consistency (e2e-audit docs-truth-1) ──────────────────
# check-doc-consistency.sh diffs root CLAUDE.md vs constitution §V model routing
# AND docs/ARCHITECTURE.md's agent table vs live agent frontmatter. It existed
# but was wired into nothing — drift accumulated invisibly.
echo "[model-doc-consistency]"
if [ -x .claude/scripts/check-doc-consistency.sh ]; then
  if cdc_out=$(bash .claude/scripts/check-doc-consistency.sh 2>&1); then
    ok "model routing + ARCHITECTURE agent table consistent with frontmatter"
  else
    fail "doc/model drift — $(echo "$cdc_out" | grep -vE 'consistent|matches' | head -3 | tr '\n' '; ')"
  fi
else
  warn "check-doc-consistency.sh missing or not executable — drift check skipped"
fi
echo

# ─── 18. Anthropic auth: OAuth-first (live-e2e T-153) ───────────────────
# Root cause of a ~$40 single-session metered bill: a workflow authenticated
# ONLY with the metered ANTHROPIC_API_KEY (and ran Opus per push). The harness
# rule is OAuth-everywhere: every workflow that can authenticate to Anthropic
# MUST offer the subscription token CLAUDE_CODE_OAUTH_TOKEN (free) — the API key
# is allowed only as a fallback, never as the sole credential.
echo "[auth-credential]"
auth_bad=0
for wf in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$wf" ] || continue
  # Does this workflow reference the metered key at all?
  if grep -qiE 'anthropic_api_key' "$wf"; then
    # Then it must also offer the OAuth token somewhere in the file.
    if ! grep -qi 'CLAUDE_CODE_OAUTH_TOKEN' "$wf"; then
      fail "OAuth-everywhere: $(basename "$wf") uses ANTHROPIC_API_KEY (metered) without offering CLAUDE_CODE_OAUTH_TOKEN (subscription) — add the OAuth token first, API key as fallback"
      auth_bad=$((auth_bad + 1))
    fi
  fi
done
[ "$auth_bad" -eq 0 ] && ok "every Anthropic-auth workflow offers the OAuth token (API key is fallback only)"
echo

# ─── dead-test detector (M-00) ──────────────────────────────────────────
# Every .claude/scripts/test/*.sh must be referenced by at least one workflow
# under .github/workflows/, otherwise it is a dead test that proves nothing —
# exactly how the 2026-07 memory audit's 87 gaps shipped "green". Reference by
# the "test/<name>" path fragment (matches `bash .claude/scripts/test/x.sh`).
echo "[dead-tests]"
# A test is "live" if a workflow either (a) invokes it explicitly by path
# (test/<name>) or (b) loops the whole directory via a scripts/test/*.sh glob.
# Correction-3 wedge avoidance (M-00): until a runner exists, an unreferenced
# test is a WARNING (with the install pointer), not a hard fail — otherwise this
# check reds main on the very PR that adds the runner. Once a glob runner is
# present, everything is covered and this passes; a future named-only runner that
# omits a NEW test is the only hard-fail path (regression, not chicken-and-egg).
dead_tests=0
if [ -d .claude/scripts/test ]; then
  # The end state is a directory-glob runner (M-00 patch) that covers every test.
  # Until it is installed, unreferenced tests are WARNINGS (with the install
  # pointer) so this check never reds the PR that introduces the runner. Once the
  # glob runner is present, every test is covered → pass. This is the same
  # advisory-first→required-later sequencing Correction 3 mandates for liveness.
  # JUSTIFIED: grep -q presence probe; 2>/dev/null hides "no workflows dir" on a fresh repo
  glob_runner=0
  grep -rqE 'scripts/test/\*\.sh' .github/workflows/ 2>/dev/null && glob_runner=1
  for t in .claude/scripts/test/*.sh; do
    [ -f "$t" ] || continue
    b=$(basename "$t")
    [ "$glob_runner" -eq 1 ] && continue
    grep -rqF "test/$b" .github/workflows/ 2>/dev/null && continue
    warn "dead test (no glob CI runner yet): .claude/scripts/test/$b — apply .claude/memory.proposed/patches/M-00-harness-test-runner.patch"
  done
fi
[ "${glob_runner:-0}" -eq 1 ] && ok "test/*.sh covered by a directory-glob CI runner" \
  || note "dead-test detector armed (advisory until the M-00 glob runner is installed)"
echo

# ─── [liveness] promoted metabolism gate (M-04-promote) ──────────────────
# Per the plan's final item + O-7 MEDIUM-1: promote ONLY the branch-local,
# deterministic committed-index-staleness check to a REQUIRED gate. The dream-
# recency and rollup-freshness checks stay ADVISORY in harness-doctor (they read
# runtime logs / need an externally-supplied wall-clock week — not derivable from
# the committed tree, so they'd reintroduce the wall-clock wedge Correction 3
# forbids). Env knobs mirror harness-doctor's so fixtures and the promotion PR can
# steer it. LIVENESS_SOFT=1 downgrades the hard fail to a warning (the grace the
# promotion PR runs under before the hard flip). No raw `date +%s` window
# comparison here — freshness is a pure mtime ordering of committed files.
LIVENESS_INDEX="${LIVENESS_INDEX:-.claude/memory/index.jsonl}"
LIVENESS_MEMORY_DIR="${LIVENESS_MEMORY_DIR:-.claude/memory}"
liveness_stale=0; liveness_detail=""
if [ -f "$LIVENESS_INDEX" ]; then
  idx_mtime=$(stat -f %m "$LIVENESS_INDEX" 2>/dev/null || stat -c %Y "$LIVENESS_INDEX" 2>/dev/null || echo 0)
  # JUSTIFIED: find may traverse a dir with no .md yet — empty result means "no memory to be stale against" (fresh)
  newest_md=$(find "$LIVENESS_MEMORY_DIR" -name '*.md' -type f -exec stat -f '%m %N' {} \; 2>/dev/null \
    || find "$LIVENESS_MEMORY_DIR" -name '*.md' -type f -printf '%T@ %p\n' 2>/dev/null)
  newest_md_mtime=$(printf '%s\n' "$newest_md" | sort -rn | head -1 | cut -d' ' -f1)
  newest_md_mtime=${newest_md_mtime%.*}; newest_md_mtime=${newest_md_mtime:-0}
  if [ "$newest_md_mtime" -gt "$idx_mtime" ]; then
    liveness_stale=1
    liveness_detail="committed memory index ($LIVENESS_INDEX) is STALE — older than the newest committed memory .md. Reindex: bash .claude/scripts/memory-index.sh rebuild (override path: LIVENESS_INDEX)"
  fi
else
  liveness_stale=1
  liveness_detail="no committed memory index at $LIVENESS_INDEX — build it: bash .claude/scripts/memory-index.sh rebuild (override path: LIVENESS_INDEX)"
fi
if [ "$liveness_stale" -eq 1 ]; then
  if [ "${LIVENESS_SOFT:-0}" = "1" ]; then
    warn "[liveness] $liveness_detail (soft/advisory: LIVENESS_SOFT=1)"
  else
    fail "[liveness] $liveness_detail (grace: run with LIVENESS_SOFT=1 to downgrade to a warning)"
  fi
else
  ok "[liveness] committed index fresh — index mtime ≥ newest committed memory .md"
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
