---
name: characterize
description: Write characterization (approval/golden-master) tests that pin the CURRENT behavior of untested legacy code BEFORE it is changed. The "no tests = no writes" safety net for brownfield adoption — distinct from tdd-loop (which drives NEW behavior red→green). Use during /adopt Phase 4, or whenever a task must touch a file flagged in .claude/state/adopt/uncharacterized-paths.txt.
when_to_use: A task needs to modify legacy code that has no tests; verify.sh's characterization gate is blocking an edit to a flagged-legacy path; /adopt Phase 4 (baseline safety); user says "characterize", "pin current behavior", "golden master", "approval test", "safety net before refactor".
model: opus
allowed-tools: Read, Glob, Grep, Edit, Write, Bash, TodoWrite
---

# Characterize

Pin what the code **does today** — not what it *should* do — so you can change it without
silently breaking it. From Michael Feathers, *Working Effectively with Legacy Code*: a
characterization test documents existing behavior; you write it, THEN change the code, and the
test tells you if you altered behavior you didn't mean to.

This is the inverse of `tdd-loop`:

| | tdd-loop | characterize |
|---|---|---|
| Goal | drive NEW behavior | freeze EXISTING behavior |
| "red" means | the feature isn't built yet | (n/a — there was no test) |
| Oracle | the spec's acceptance criteria | the code's current output |
| When | greenfield / new feature | brownfield / untested legacy |

## The loop

1. **Find a seam.** Identify where you can observe the code's output without changing it — a
   pure function's return, an HTTP handler's response, a CLI's stdout, a rendered DOM. If there's
   no seam, introduce the *minimum* one (extract a function, inject a dependency) — that itself is
   a behavior-preserving refactor; do it tiny and commit separately.
2. **Capture current output (the golden master).** Run the code against representative inputs
   (include real production-shaped data + edge cases from the hotspots list). Record exactly what
   it returns/emits — bugs included. You are documenting reality, not correctness.
3. **Write the test asserting that captured output.** Name it so the gate recognizes it:
   `<name>.characterization.test.<ext>` (JS/TS) or `test_<name>_characterization.py` (Python),
   co-located or under the repo's test root. Use the repo's existing test runner (see
   `AGENTS.md` / atlas).
4. **Run it — it must PASS immediately** (it asserts what the code already does). A failing
   characterization test means your captured oracle is wrong; fix the capture, not the code.
5. **Record the ledger.** Write `verify/<date>/<task>/green.log` (it passed) so the TDD-ledger
   gate is satisfied. There is no `red.log` requirement for characterization — note "characterization
   (no prior test)" in the task instead.
6. **Now you may change the code.** Make your change; re-run the characterization test. If it
   fails, you changed observable behavior — decide deliberately: update the golden master (with a
   one-line rationale) or revert.
7. **Remove the path from the manifest.** Once a flagged-legacy file has a characterization test,
   delete its glob (or the file) from `.claude/state/adopt/uncharacterized-paths.txt` so autopilot
   and `verify.sh` stop blocking it.

## For NEW features in untested legacy: sprout, don't touch

If the task ADDS behavior (not modifies), use Feathers' **Sprout Method/Class**: write the new
logic in a fresh, fully-TDD'd function/class and call it from the legacy code with the smallest
possible edit. The legacy body stays untouched — so you never owe it a characterization test, and
the new code gets normal `tdd-loop` red→green rigor.

## Hard rules

- **Characterize before you change. No tests = no writes** (verify.sh enforces; `SKIP_CHAR_GATE=1`
  is a human-only override, never an autopilot one).
- **Document reality, including bugs.** If the legacy code returns the wrong total, the
  characterization test asserts the wrong total. Fixing the bug is a *separate, later* task with
  its own spec — now made safe because the test will flag the behavior change.
- **Smallest seam.** Don't refactor broadly to make code testable; introduce the minimum seam,
  commit it alone, then characterize.
- **Hotspots first.** Characterize the churn×LOC hotspots from `ADOPTION-REPORT.md` before the
  long tail — that's where factory-driven change is most likely and most dangerous.

## References
- Michael Feathers, *Working Effectively with Legacy Code* (characterization tests, seams, sprout/wrap)
- `docs/research/brownfield-onboarding.md` (the adoption research brief)
- `.claude/skills/tdd-loop/SKILL.md` (the greenfield counterpart)
- `.claude/commands/adopt.md` (Phase 4 invokes this)
