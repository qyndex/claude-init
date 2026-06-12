# Verification report — root CLAUDE.md audit (init)

- **Date:** 2026-06-12
- **Change:** Documentation-only. Audited root `CLAUDE.md` against the codebase and fixed four drifts:
  1. `validate.sh` category count corrected 14 → 16 (added constitution-size, ruleset-coverage); noted `--json` mode on `validate.sh` and `harness-doctor.sh`.
  2. Added `anti-slop-reviewer` to the Sonnet 4.6 model routing list (matches `.claude/agents/quality/anti-slop-reviewer.md` frontmatter `model: sonnet`).
  3. Hook lifecycle table: `PreToolUse:Write` row corrected to `Write|Edit|NotebookEdit` matcher with `pre-edit-constitution-guard.sh` + `pre-write-secret-scan.sh` (matches `settings.json:451-464`).
  4. Security invariants: constitution write-block now names its enforcing hook (`pre-edit-constitution-guard.sh`).
- **Files changed:** `CLAUDE.md` (root) only. No scripts, hooks, configs, or CI touched.

## Evidence

```
$ bash .claude/scripts/validate.sh
✓ all checks passed (with 140 warnings)   # 140 warnings pre-existing, unrelated
```

All 16 categories pass, including `[constitution-size]` (206/300 lines) and `[ruleset-coverage]`.

## Hook exit-2/stderr audit (follow-up, same session)

`stop-verify.sh` was fixed and installed by the operator (root `CLAUDE.md` excluded from prod-file check; block reasons now on stderr). A full sweep of every `exit 2` site across `.claude/hooks/` then found the same defect class in three more hooks. Fixed copies are staged in this directory; each diff is 3-4 added lines (stderr echo + comment), stdout JSON contracts untouched.

| Hook | Sites | Defect | Staged fix |
|---|---|---|---|
| `pre-bash-guard.sh` | 112, 135 | Deny reason interpolates `$pattern`/`$seg` unescaped into stdout JSON — patterns contain `\.` (invalid JSON escape), so the JSON breaks exactly when the hook fires and the harness falls back to empty stderr. Confirmed live. | `pre-bash-guard.sh.fixed` |
| `subagent-stop.sh` | 73, 89 | NEXUS-block reason only in stdout `additionalContext` JSON; nothing on stderr with exit 2. A blocked swarm agent gets no reason. | `subagent-stop.sh.fixed` |
| `pre-edit-constitution-guard.sh` | 107 | stdout JSON is valid and currently displayed, but exit 2 + empty stderr is fragile; reason now mirrored to stderr. | `pre-edit-constitution-guard.sh.fixed` |
| `pre-bash-dep-freshness.sh` | — | Clean: uses `permissionDecision` JSON + exit 0 (correct pattern). | none needed |
| `pre-spawn-cost-gate.sh` | — | Clean: JSON + exit 0. | none needed |

### Evidence

```
$ bash verify/2026-06-12-claude-md-audit/test-exit2-stderr.sh
passed=11 failed=0       # every blocked path: exit 2 + non-empty stderr; every allowed path: exit 0
$ bash .claude/scripts/test/pre-bash-guard-bypass.sh        # 15/15 pass (baseline, contract preserved)
$ bash .claude/scripts/test/pre-edit-constitution-guard.sh  # 17/17 pass (baseline, contract preserved)
```

Install (operator, via `!` or terminal — hooks are constitution-class write-protected):

```bash
for f in pre-bash-guard subagent-stop pre-edit-constitution-guard; do
  cp "verify/2026-06-12-claude-md-audit/$f.sh.fixed" ".claude/hooks/$f.sh" && chmod +x ".claude/hooks/$f.sh"
done
bash .claude/scripts/test/pre-bash-guard-bypass.sh && bash .claude/scripts/test/pre-edit-constitution-guard.sh
```
