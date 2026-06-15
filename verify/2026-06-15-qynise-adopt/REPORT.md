# Brownfield adoption test — qynise

Date: 2026-06-15
Method: isolated git worktree at qynise's pre-harness commit `d58ed17d` (#317),
ran the full six-phase `/adopt` flow with the current claude-init factory
(`origin/main` @ 5ab9847). **Real qynise repo never touched.**

## Verdict

**The harness's brownfield adoption flow works as designed.** Every mechanical
phase did what `docs/ADOPTION.md` promises; the two human safety gates held; the
characterization capability proved out on real production code. 4 harness-quality
findings surfaced (the point of the test) — none block adoption.

## Phase-by-phase result

| Phase | Result | Evidence |
|---|---|---|
| Step 0 — install/reconcile | ✅ | 7/7 promises verified on disk: .claude/ backed up to `.brownfield-backup/<ts>` (116-path MANIFEST), their 11 cmds + 6 hooks preserved, their settings→`.brownfield-orig` (md5 match), root CLAUDE.md untouched (md5 match), .github 54 files no-clobber, AGENTS.md + project-conventions.md drafted |
| Phase 1 — archaeology (GATE 1) | ✅ | hotspots.txt (top-20 by churn×LOC: models.py, api.ts, graph.py…), legacy-safety globs (`src/**`,`web/**`), coverage baseline, 4 sharp [OQ]s incl. pre-commit deadlock |
| **Human-only approve gate** | ✅ | `adopt-state.sh approve 1` REFUSED agent self-approval — demanded user `touch .claude/state/allow-adopt-approve` (single-use, gitignored) |
| Phase 2 — reconcile | ✅ | extract-conventions → AGENTS.md correctly IDs Python/pip-uv/pytest/ruff |
| Phase 3 — import | ✅ | 63 ADRs (of qynise's 61 docs/adr + 102 docs/plan) → `.claude/memory/decisions/` |
| Phase 4 — characterization (GATE 2) | ✅ | golden-master for `src/orchestrator/state.py` reducers — **7/7 pass on live code** (dedup-by-signature, unhashable-tail, sorted stable_repr). `characterization: true` green-only ledger recognized |
| Phase 5 — backlog | ✅ | 5 adoption tasks (T-A01..A05) appended to tasks/TASKS.md from real findings |
| Phase 6 — handoff | ✅ | state=approved-6; harness-doctor leaves the post-adoption setup checklist |

## Final health

- `validate.sh`: **17 pass / 4 fail** — the 4 are findings below, not mechanics.
- `harness-doctor`: 26 checks; all SECURITY-critical green
  (disableBypassPermissionsMode=disable, hooks exec, constitution ≤300, no @latest,
  no bypass). The ✗ are expected operator post-adoption steps (sync initiative state,
  install routines, set OAuth secret, activate live ruleset, wire deploy).

## Realistic friction (expected, documented)

- **No venv/deps in a fresh worktree** — qynise's suite can't run until `pip install`;
  `pyproject.toml` sets `asyncio_mode` needing pytest-asyncio. Phase 4 needs the
  project toolchain installed first (archaeology's coverage [OQ] flags it). Proved the
  char test green via a minimal venv.
- **semgrep/gitleaks absent locally** → archaeology security scan degraded to
  "(not available)" — see finding #4.

## Harness-quality findings (file back into claude-init)

1. **Factory `tasks/TASKS.md` references `spec:003` with no `specs/{active,archive}/003`
   file** — `specs/archive/` ships only `.gitkeep`; spec 003 exists only in `plans/`.
   The `artifacts` gate correctly flags it on ANY fresh repo. Fix: ship the spec file
   or drop the dangling task ref.
2. **`reconcile-claude-dir.sh` uses `cp -R` (clobber) for `.claude/commands` +
   `.claude/hooks`**, unlike the `cp -Rn` used for scaffold/.github. Safe here (no name
   collision) but a custom hook/command sharing a factory filename would be silently
   overwritten. Fix: `cp -Rn` + collision→[OQ], matching the other buckets.
3. **`model-doc-consistency` extractor fails to parse a CLAUDE.md that DOES contain the
   §V model table** — validator brittleness; investigate the regex/awk.
4. **`semgrep`/`gitleaks` absent → silent "(not available)"** in archaeology security
   scan rather than a loud "install these to scan" — a quiet coverage gap.

## Fixes applied + reverified (2026-06-15)

All 4 findings FIXED in claude-init (agent-writable `.claude/scripts/`) and reverified
by re-running the full adoption against fresh qynise worktrees. Adopted-qynise
validate.sh dropped **4 fails → 2** (the 2 remaining are qynise's OWN backlog, not
harness bugs: custom commands need `disable-model-invocation`, demo-gate.yml metered key).

1. **F1 — dangling spec:003** (was mis-triaged as not-a-bug; it IS real). Root cause:
   `setup.sh` template-clean MOVES factory specs 001-003 to `docs/factory-history/`,
   but its awk only stripped `## Active` task lines — factory tasks T-129/130/131
   (spec:003, phase 9) sit ABOVE `## Active`, so they survived while the spec moved
   → dangling ref → `artifacts` gate fails. **Fix:** awk now drops any
   `- [.] T-N … spec:00[1-3]` line anywhere. Verified: 0 dangling refs, artifacts PASS.
2. **F2 — cp -R clobber.** Split FACTORY_DIRS (overwrite) from new MERGE_DIRS
   (commands+hooks, `cp -Rn` no-clobber) + collision→[OQ]. Verified: a custom
   `pre-bash-guard.sh` survives, factory file coexists, collision reported to backup.
3. **F3 — model-doc brittleness.** `check-doc-consistency.sh` now requires the §V table
   only in the constitution (`.claude/CLAUDE.md`); a brownfield root `CLAUDE.md` without
   it skips the cross-diff (exit 0) instead of erroring. Verified greenfield still strict,
   brownfield passes; adopted-qynise model-doc-consistency PASS.
4. **F4 — silent security degrade.** `adopt-archaeology.sh` now emits `::warning::` +
   "⚠️ NOT SCANNED … coverage is OFF" + an [OQ] ("do NOT approve Phase 1 as clean") when
   semgrep/gitleaks absent. Verified all three fire.

claude-init validate.sh: **21/21 green** after all edits. shellcheck clean.

## Cleanup
All test worktrees + `.venv-char` + temp factory exports removed; real qynise pristine
(`main @ 021a3632`). Fixed scripts: check-doc-consistency.sh, reconcile-claude-dir.sh,
adopt-archaeology.sh, setup.sh.
