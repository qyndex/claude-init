# M-04 liveness probes — evidence bundle (2026-07-23)

Advisory liveness probes added to `.claude/scripts/harness-doctor.sh` in the
"Memory-plane health" section. All probes are **warn/pass only — never fail**
(Correction 3: hard-fail deferred to M-04-promote in `validate.sh`).

## Probes (env-overridable, mirroring gc-suite.sh's GC_VERIFY_AGE_DAYS)

| Probe | Check label | Overrides |
|---|---|---|
| Stale committed index | `memory: committed index fresh` | `LIVENESS_INDEX`, `LIVENESS_MEMORY_DIR` |
| Dead dream | `memory: dream has run recently` | `LIVENESS_DREAM_DIR`, `LIVENESS_DREAM_FAILS` (default 3) |
| Rollup gap | `memory: rollup freshness` | `LIVENESS_ROLLUP_DIR`, `LIVENESS_ROLLUP_WEEKS` (default 2), `LIVENESS_NOW_WEEK` |

The index probe is **branch-local + deterministic**: it compares the committed
index mtime to the newest committed memory `*.md`. A reindex PR fixes it, so the
condition is falsifiable (not a wall-clock-since-dream check). The rollup probe
refuses to invent a wall clock — without `LIVENESS_NOW_WEEK` it warns "unknown".

## Files

- `doctor-report.json` — captured `harness-doctor.sh --json` filtered to the
  liveness + metabolism checks (real repo, `HARNESS_DOCTOR_SKIP_SPAWN=1`).
- Fixtures are injected hermetically by `.claude/scripts/test/liveness-probes.sh`
  via `mktemp` + the env-override vars (no real dream/auth, `LIVENESS_NOW_WEEK`
  pins the clock). Representative fixture shapes captured under `fixtures/`
  (dead-dream `*.log` samples are repo-`.gitignore`d — the test regenerates them).

## TDD ledger

- `verify/2026-07-23/M-04/red.log` — exit 1, 8 assertions failing (probes absent).
- `verify/2026-07-23/M-04/green.log` — exit 0, 9/9 passing (probes added).
