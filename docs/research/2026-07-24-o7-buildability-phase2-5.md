# O-7 Buildability Re-Review — Phase 2-5

> Researcher agent, 2026-07-24. Read-only (no Bash available to the reviewer —
> verdicts rest on reading exact code paths, not live execution; two items need a
> live red-baseline captured before build). One of three O-7 dimensions.

## Verdicts

| Item | Verdict | Key evidence |
|---|---|---|
| M-10 | BUILDABLE | `0000-template.md:4,8,13,23-24` split schema (frontmatter `status:` + body `- **Status**:`); no validate.sh rule rejects body-bullet form |
| M-11 | BUILDABLE (scope understated) | no `--supersedes` case in `memory-index.sh`; write path 100% new, read path (recall −5) already live/unfed |
| M-12 | BUILDABLE | `MEMORY.md:24` literally "(none yet)"; file unguarded |
| M-13-14 | BUILDABLE | noise-floor (`memory-recall.sh:70` score>0 not hits>0) + missing extensions (`memory-index.sh:42`) confirmed |
| M-15-16-17 | BUILDABLE, **guarded** | scope-bug `subagent-context.sh:61-65`; that file IS hook-deny-listed → staged patch |
| M-18 | BUILDABLE (scope understated) | arg-ignore confirmed `memory-rollup.sh:34-70,132-138`; CI-workflow half guarded |
| M-19 | BUILDABLE (doc-drift risk) | depends on M-01b; plan.json vs markdown disagree — use markdown |
| M-20 | NEEDS-PRECONDITION-FIX | asymmetry count unverified; mechanism is id/endswith mismatch at `memory-index.sh:54,164-166,234` |
| M-21-22 | BUILDABLE but MISLABELED | zero existing target file — greenfield, not an edit |
| M-23-26 | BUILDABLE | `mirror-user-state.sh:19-20` hardcodes `$HOME/.claude`, no `CLAUDE_CONFIG_DIR` |
| M-04-promote | BUILDABLE | dep M-04 built+tested; ruleset-required half guarded |

## Guarded-files map (the decisive operational finding)

`.claude/scripts/` is **NOT** on `pre-edit-constitution-guard.sh`'s deny-list (lines 89-104). Deny-listed: `.claude/hooks/*`, `.claude/rules/*`, `.claude/agents/*`, `.claude/skills/*`, `.mcp.json`, `.github/workflows/*`, `.github/rulesets/*`, `.github/CODEOWNERS`, `tasks/TASKS.md`, `specs/active/*`, `.claude/settings.json`, `.claude/CLAUDE.md`.

- **Directly agent-writable** (plain edit, no staging): M-10, M-11, M-12 (`MEMORY.md` unguarded), M-13-14, M-18 (script half), M-19 (script half), M-20, M-21-22, M-23-26 (`mirror-user-state.sh`), M-04-promote (`validate.sh` half).
- **Needs staged patch**: M-15-16-17 (`subagent-context.sh` is a hook), M-18 (new/edited `.github/workflows/*`), M-04-promote (ruleset-required check name in `.github/rulesets/main-protection.json`, if not already folded into `harness-validate`'s aggregate).

## Pre-build precondition captures required (reviewer had no Bash)

1. **M-20**: run `bash .claude/scripts/memory-index.sh verify` live, record real asymmetry count as red baseline (not the plan's unverified "9").
2. **M-18**: run `bash .claude/scripts/memory-rollup.sh weekly 2026-W25` live, confirm it silently ignores the arg.

## Scope relabels the plan should absorb

- **M-21-22** → "new script" not "fix" (no `hot.md`/decay logic exists).
- **M-11** → split write-path (new index subcommand + YAML frontmatter mutation, sed-on-YAML risk) vs read-path (already live).
- **M-18** → backfill needs an env-clock (`ROLLUP_NOW`) loop, not a one-line arg-read.
- **M-20** → cite the id/`endswith` mismatch mechanism (`memory-index.sh:54,164-166,234`), not a generic "back_ref matcher."

## Low-severity docs fix
`verify/2026-07-23-memory-plan-review/plan.json` M-01b/corrections[0] still carries the twice-superseded auth fix (apiKeyHelper, not `--bare`). M-19 implementer must read the markdown. Patch when convenient.

## DAG check
Phase 2-5 declared deps vs §2 landing order: internally consistent, no forward references found (corroborates round-2, not an exhaustive 25-item re-derivation).
