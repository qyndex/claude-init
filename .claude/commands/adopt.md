---
description: Brownfield adoption — bring an existing/legacy repo under the factory framework via six HUMAN-GATED phases (archaeology → reconcile → import → baseline → backlog → handoff). Read-only until you approve Phase 1. No phase skipping.
argument-hint: "<auto|start|reconcile|import|baseline|backlog|handoff|approve <n>|status> [--dry-run]"
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, TodoWrite
disable-model-invocation: true
---

# /adopt — Brownfield adoption

Bring a real, existing project under the factory. Six phases, each STOPS for your approval
(`/adopt approve <n>`) before the next can run — agents derail at phase *transitions*, so every
transition is human-gated. Full operator guide: [docs/ADOPTION.md](../../docs/ADOPTION.md).

**Hands-off?** `/adopt auto` self-drives the mechanical phases (2,3,5) and **hard-stops only at the
two safety gates**: Phase 1 (review the archaeology report + legacy-safety manifest) and Phase 4
(review the characterization tests). Run it, approve gate 1, run it again (it advances to gate 4),
approve gate 4, run it once more (it finishes). Two human decisions instead of six.

> **Before `/adopt`:** the factory `.claude/` must already be in the repo. If the repo had its
> OWN `.claude/`, reconcile it FIRST (never `cp -nr` over it):
> `bash <factory-clone>/.claude/scripts/reconcile-claude-dir.sh --from <factory-clone> --into .`

```bash
verb="${1:-status}"; shift 2>/dev/null || true
S=".claude/scripts/adopt-state.sh"

# Phase-3 doc/ADR sweep (shared by `import` and `auto`): copy existing docs into memory as
# REFERENCES (originals stay the source of truth — never lossy-convert), then re-index.
_import_docs() {
  mkdir -p .claude/memory/decisions/imported
  local found=0 f base dest
  for f in $(find docs adr decisions architecture* ARCHITECTURE* PRD* -type f -iname '*.md' 2>/dev/null | grep -v brownfield-backup | head -50); do
    base=$(basename "$f"); dest=".claude/memory/decisions/imported/${base}"
    [ -e "$dest" ] && continue
    { printf '<!-- imported from %s at %s — original is source of truth -->\n\n' "$f" "$(date -Iseconds)"; cat "$f"; } > "$dest"
    found=$((found + 1))
  done
  echo "→ Imported $found doc(s) → .claude/memory/decisions/imported/ (originals untouched)."
  [ -f .claude/scripts/memory-index.sh ] && bash .claude/scripts/memory-index.sh backfill >/dev/null 2>&1 || true
}

# Phase-6 gate verification (brownfield-3): every required check named in the ruleset
# must exist as a workflow job, or every brownfield PR hangs pending-forever.
_verify_gates() {
  local rs=.github/rulesets/main-protection.json missing=0 ctx
  { [ -f "$rs" ] && command -v jq >/dev/null 2>&1; } || { echo "→ gate check skipped (no ruleset or no jq)"; return 0; }
  while IFS= read -r ctx; do
    [ -z "$ctx" ] && continue
    grep -qE "^  ${ctx}:[[:space:]]*$" .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null \
      || { echo "  ✗ required check '$ctx' has NO workflow job in .github/workflows/"; missing=1; }
  done < <(jq -r '.. | objects | .context? // empty' "$rs" | sort -u)
  if [ "$missing" = 1 ]; then
    echo "✗ the ruleset requires checks no workflow provides — PRs will never merge."
    echo "  Fix: copy the factory .github (reconcile-claude-dir.sh does this) or edit $rs."
    return 1
  fi
  echo "→ all ruleset required checks map to workflow jobs ✓"
}

case "$verb" in
  auto)         # Self-driving: chain the mechanical phases; HARD-STOP only at safety gates 1 & 4.
    cur="$(bash "$S" phase 2>/dev/null || echo 0)"

    # ── Not started → run Phase 1, then STOP at SAFETY GATE 1 (human-only review) ──
    if [ "${cur:-0}" -lt 1 ]; then
      bash .claude/scripts/adopt-archaeology.sh
      echo
      echo "════════ AUTO PAUSED — SAFETY GATE 1 (human-only) ════════"
      echo "Phase 1 archaeology done. REVIEW ADOPTION-REPORT.md — confirm the legacy-safety globs"
      echo "(.claude/state/adopt/uncharacterized-paths.txt) and resolve [OQ]s."
      echo "Then:  /adopt approve 1  &&  /adopt auto    (auto-runs phases 2–3, stops at gate 4)"
      exit 0
    fi

    # ── Phase 1 approved & below 4 → auto-run phases 2 & 3, then STOP at SAFETY GATE 4 ──
    if bash "$S" gate 1 >/dev/null 2>&1 && [ "${cur:-0}" -lt 4 ]; then
      if [ "${cur:-0}" -lt 2 ]; then
        bash .claude/scripts/extract-conventions.sh --into . >/dev/null 2>&1
        bash "$S" set 2 reconcile >/dev/null; bash "$S" approve 2 >/dev/null
        echo "✓ auto-advanced Phase 2 (reconcile) — conventions drafted to AGENTS.md"
      fi
      if [ "$(bash "$S" phase)" -lt 3 ]; then
        _import_docs
        # brownfield-5: the issue import is NEVER muted — a failed read must refuse
        # Phase-3 auto-approval instead of silently severing the backlog forever.
        import_rc=0
        if [ -f .claude/state/adopt/issues-imported.done ]; then
          echo "→ issues already imported ($(cat .claude/state/adopt/issues-imported.done))"
        elif command -v gh >/dev/null 2>&1; then
          bash .claude/scripts/import-issues-once.sh || import_rc=$?
        else
          echo "→ gh not available — issue import SKIPPED (run import-issues-once.sh later, or seed tasks/TASKS.md manually)"
        fi
        if [ "$import_rc" -ne 0 ]; then
          echo
          echo "✗ AUTO HALTED — Phase 3 issue import FAILED (rc=$import_rc). NOT auto-approving Phase 3."
          echo "  No sentinel was written — fix gh auth/network, then re-run: /adopt auto"
          exit 1
        fi
        bash "$S" set 3 import >/dev/null; bash "$S" approve 3 >/dev/null
        echo "✓ auto-advanced Phase 3 (import) — docs → memory, issues → tasks/TASKS.md"
      fi
      oq="$(grep -c '\[OQ\]' ADOPTION-REPORT.md 2>/dev/null || echo 0)"
      echo
      echo "════════ AUTO PAUSED — SAFETY GATE 4 (characterization) ════════"
      [ "${oq:-0}" -gt 0 ] && echo "  note: ${oq} unresolved [OQ](s) in ADOPTION-REPORT.md — clear via /clarify when convenient."
      echo "Phase 4 is next and is mine to do, but YOURS to approve: I must write CHARACTERIZATION"
      echo "TESTS for the hotspots before the factory may touch any legacy ('no tests = no writes')."
      echo "I will now: invoke the 'characterize' skill on .claude/state/adopt/hotspots.txt, prune"
      echo "characterized globs from uncharacterized-paths.txt, run 'bash $S set 4 baseline', and show"
      echo "you the tests. After you're satisfied:  /adopt approve 4  &&  /adopt auto   (finishes 5–6)."
      exit 0
    fi

    # ── Phase 4 approved → auto-run phases 5 & 6 to completion ──
    if bash "$S" gate 4 >/dev/null 2>&1; then
      if [ "${ADOPT_SKIP_GATE_CHECK:-0}" != 1 ] && ! _verify_gates; then
        echo "✗ AUTO HALTED before Phase 6 — fix the gate layer, then re-run /adopt auto (or ADOPT_SKIP_GATE_CHECK=1 to override deliberately)."
        exit 1
      fi
      [ -f ADOPTION-REPORT.md ] && [ -f .claude/scripts/findings-to-tasks.sh ] && \
        bash .claude/scripts/findings-to-tasks.sh ADOPTION-REPORT.md --priority security --source adopt-backlog >/dev/null 2>&1 || true
      bash "$S" set 5 backlog >/dev/null; bash "$S" approve 5 >/dev/null
      echo "✓ auto-advanced Phase 5 (backlog) — remediation tasks created (tag strategies in tasks/TASKS.md)"
      [ -f .claude/scripts/seed-patterns.sh ] && bash .claude/scripts/seed-patterns.sh auto >/dev/null 2>&1 || true
      command -v gh >/dev/null 2>&1 && [ -f .claude/scripts/tasks-to-issues.sh ] && bash .claude/scripts/tasks-to-issues.sh --all >/dev/null 2>&1 || true
      bash "$S" complete
      echo "✓ AUTO COMPLETE — adoption finished. Repo now uses the standard 8-phase workflow."
      echo "  Any remaining uncharacterized-paths.txt globs still gate autopilot. Next: /triage"
      exit 0
    fi

    # ── Otherwise: parked on a human gate that isn't approved yet ──
    echo "Auto is parked on a human gate (phase ${cur}, status $(bash "$S" status 2>/dev/null))."
    echo "  Gate 1 pending → review ADOPTION-REPORT.md, then: /adopt approve 1 && /adopt auto"
    echo "  Gate 4 pending → characterize hotspots + 'bash $S set 4 baseline', then: /adopt approve 4 && /adopt auto"
    ;;

  start)        # Phase 1 — Archaeology (READ-ONLY)
    bash .claude/scripts/adopt-archaeology.sh
    echo "→ Review ADOPTION-REPORT.md, resolve every [OQ], then: /adopt approve 1 && /adopt reconcile"
    ;;

  reconcile)    # Phase 2 — Config reconciliation + convention extraction
    bash "$S" gate 1 || exit 1
    bash .claude/scripts/extract-conventions.sh --into .
    echo "→ Conventions drafted to AGENTS.md + .claude/rules/project-conventions.md (REVIEW & REFINE)."
    if ls .claude/CLAUDE.md.brownfield-orig >/dev/null 2>&1; then
      echo "→ Your original CLAUDE.md is at .claude/CLAUDE.md.brownfield-orig — migrate project conventions into AGENTS.md; the factory CLAUDE.md governs process. (Conflicts are [OQ] in ADOPTION-REPORT.md → /clarify.)"
    fi
    bash "$S" set 2 reconcile
    echo "→ Resolve [OQ]s, then: /adopt approve 2 && /adopt import"
    ;;

  import)       # Phase 3 — Knowledge import (docs/ADRs + one-time issue ingest)
    bash "$S" gate 2 || exit 1
    _import_docs                                  # 3a. docs/ADRs → memory (references)
    # 3b. One-time GitHub issue ingest (self-terminating; see import-issues-once.sh header).
    if command -v gh >/dev/null 2>&1; then
      bash .claude/scripts/import-issues-once.sh "$@" || { echo "✗ issue import failed — no sentinel written; fix gh and re-run /adopt import"; exit 1; }
    else
      echo "→ gh not available — skipped issue import. Run import-issues-once.sh later, or seed tasks/TASKS.md manually."
      bash "$S" set 3 import
    fi
    echo "→ Review tasks/TASKS.md + imported memory, then: /adopt approve 3 && /adopt baseline"
    ;;

  baseline)     # Phase 4 — Baseline safety (characterization tests) — AGENT-DRIVEN
    bash "$S" gate 3 || exit 1
    echo "Phase 4 — Baseline safety. This step is agent-driven, not fully scripted:"
    echo "  1. Invoke the 'characterize' skill (.claude/skills/characterize/SKILL.md)."
    echo "  2. Write characterization tests for the hotspots in .claude/state/adopt/hotspots.txt"
    echo "     (highest churn×LOC first). Each must PASS immediately (it pins current behavior)."
    echo "  3. As each flagged path gains a characterization test, REMOVE its glob from"
    echo "     .claude/state/adopt/uncharacterized-paths.txt so verify.sh + autopilot unblock it."
    echo "  4. Record the real current coverage % as the floor in ADOPTION-REPORT.md."
    echo "When the hotspots are characterized: /adopt approve 4 && /adopt backlog"
    echo "(adopt-state is advanced by the agent once characterization is done: bash $S set 4 baseline)"
    ;;

  backlog)      # Phase 5 — Remediation backlog (legacy/vuln/migration → tasks)
    bash "$S" gate 4 || exit 1
    if [ -f ADOPTION-REPORT.md ] && [ -f .claude/scripts/findings-to-tasks.sh ]; then
      # The report's vuln/security/legacy sections carry `- [ ]` items; convert them to tasks.
      bash .claude/scripts/findings-to-tasks.sh ADOPTION-REPORT.md --priority security --source adopt-backlog || true
    fi
    echo "→ Remediation tasks created. Tag each with a migration strategy in tasks/TASKS.md:"
    echo "   strangler-fig (service/module replacement) · expand-contract (DB/API breaking change) ·"
    echo "   codemod (>50 call sites) · sprout-method (new behavior in untested legacy)."
    bash "$S" set 5 backlog
    echo "→ Review the backlog, then: /adopt approve 5 && /adopt handoff"
    ;;

  handoff)      # Phase 6 — Handoff to the normal 8-phase workflow
    bash "$S" gate 5 || exit 1
    if [ "${ADOPT_SKIP_GATE_CHECK:-0}" != 1 ] && ! _verify_gates; then
      echo "  (override only deliberately: ADOPT_SKIP_GATE_CHECK=1 /adopt handoff)"
      exit 1
    fi
    [ -f .claude/scripts/seed-patterns.sh ] && bash .claude/scripts/seed-patterns.sh auto >/dev/null 2>&1 || true
    if command -v gh >/dev/null 2>&1 && [ -f .claude/scripts/tasks-to-issues.sh ]; then
      bash .claude/scripts/tasks-to-issues.sh --all >/dev/null 2>&1 || true
    fi
    bash "$S" complete
    echo "✓ Adoption complete. The repo now uses the standard 8-phase workflow."
    echo "  Remaining uncharacterized-paths.txt globs still gate autopilot — clear them as you characterize."
    echo "  Next: /triage (see the imported + remediation backlog) or /implement next."
    ;;

  approve)      bash "$S" approve "${1:?usage: /adopt approve <phase-number>}" ;;
  status)       bash "$S" show 2>/dev/null || echo "No adoption in progress. Start with: /adopt start" ;;
  *)            echo "Usage: /adopt <start|reconcile|import|baseline|backlog|handoff|approve <n>|status> [--dry-run]" ;;
esac
```

## The six phases at a glance

| Phase | Verb | What it does | Gate |
|---|---|---|---|
| 1 | `start` | Read-only archaeology → `ADOPTION-REPORT.md` (stack, hotspots, deps/vulns, coverage, safety manifest). **No code touched.** | approve 1 |
| 2 | `reconcile` | Extract project conventions → `AGENTS.md` + rule; surface `.claude/` collisions as `[OQ]`. | approve 2 |
| 3 | `import` | Docs/ADRs → memory (referenced); existing GitHub issues → TASKS.md **once** (self-terminating). | approve 3 |
| 4 | `baseline` | Characterization tests for hotspots (the `characterize` skill); record coverage floor; unblock characterized paths. | approve 4 |
| 5 | `backlog` | Legacy/vuln/migration items → prioritized tasks, each tagged with a migration strategy. | approve 5 |
| 6 | `handoff` | Seed patterns, project tasks→issues, mark complete. Repo joins the normal workflow. | — |

## Why it's safe for autonomy
After Phase 1, **every** source zone is in `.claude/state/adopt/uncharacterized-paths.txt`. Until a
zone has a characterization test, `verify.sh` FAILS any edit to it and the overnight autopilot SKIPS
tasks touching it ("no tests = no writes"). Autonomy can only operate on characterized code or
genuinely-new (sprouted) code. You lift the restriction one zone at a time, deliberately.

$ARGUMENTS
