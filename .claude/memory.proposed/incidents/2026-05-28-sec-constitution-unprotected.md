---
name: 2026-05-28-sec-constitution-unprotected
description: Audit-uncovered systemic gap — the harness constitution and security-critical files were unprotected from agent writes despite CLAUDE.md claiming otherwise.
metadata:
  type: incident
  status: open
status: open
created: 2026-05-29
last_verified: 2026-05-29
---

# Incident: Constitution and security-critical files unprotected from agent writes

- **Date**: 2026-05-28
- **Severity**: SEV1
- **Status**: open
- **Duration**: 2026-05-27 (harness v2.0.0 release) → ongoing until spec 001 phase 1 ships
- **Authors**: @claude (via five-agent audit on 2026-05-28), @shravan-qyndex

## Summary

A five-agent audit (architect, security, reviewer, verifier, researcher) of the `claude-init` harness on 2026-05-28 discovered that the security invariants documented in `.claude/CLAUDE.md §VII` and `§X` and `CLAUDE.md` "Security invariants" are documentation theater for the most critical claim: **the constitution itself, the hooks that enforce all guards, the settings that define permissions, and the workflows that gate CI are all writable by Claude with zero hook-level protection**. No code path blocks a Claude session from rewriting `pre-bash-guard.sh` to `exit 0`, after which every other documented guard (destructive-command block, secret scan, no-issue-authority) becomes bypassable. Additionally, `pre-bash-guard.sh` itself is bypassable via at least four classes of input that the regex-based splitter does not parse (command substitution `$(...)`, env-var indirection `$X`, no-space variants `python -c"…"`, process substitution `. <(curl …)`). The `evidence-gate` workflow exists and exits non-zero on UNPROVEN ACs, but is **not in `.github/rulesets/main-protection.json` required checks** — so PRs with UNPROVEN evidence can still merge. The sandbox is `enabled: false` and the network allow-list below it is dead config.

The harness has not yet been used in production for any third-party project, so no known exploitation has occurred. However, every operator who adopts the harness in its v2.0.0 state inherits the gap.

## Timeline (all times UTC)

| Time              | Event                                                                                                                                                          |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 2026-05-27 ~10:00 | Harness v2.0.0 released with CLAUDE.md §VII / §X claiming the protections                                                                                      |
| 2026-05-28 22:00  | Operator (@shravan-qyndex) requests five-agent audit                                                                                                           |
| 2026-05-28 22:35  | Security agent surfaces F-1 (constitution unprotected), F-2 (bypass via `$()`), F-3 (env-var indirection), F-4 (no-space variants), F-5 (process substitution) |
| 2026-05-28 22:40  | Verifier agent surfaces evidence-gate not in required checks                                                                                                   |
| 2026-05-28 22:45  | All five agents complete; gap synthesized                                                                                                                      |
| 2026-05-28 23:00  | Spec `specs/active/001-harness-hardening.md` authored                                                                                                          |
| 2026-05-29+       | Phase 1 fixes ship (AC-1..AC-4 of spec 001)                                                                                                                    |

## Root cause

Three interacting causes:

1. **`.claude/hooks/pre-write-secret-scan.sh:22-30`** — the deny-list checks for `.env`, `.ssh`, `.pem`, `.tfvars`, `credentials` but contains no entries for `.claude/CLAUDE.md`, `.claude/hooks/**`, `.claude/settings.json`, `.mcp.json`, `.github/workflows/**`, `.github/rulesets/**`. The constitution claim "`.claude/CLAUDE.md` is intentionally blocked from Claude writes" was never wired to code.
2. **`.claude/hooks/pre-bash-guard.sh:76`** — the chained-command splitter is `sed -E 's/[;|&]+/\n/g'`. It does not parse `$(...)`, backticks, or process substitution. The regex patterns (`python3? +-c +`, `eval +`, `base64 +(-d|--decode) +`, etc.) require space delimiters that bash does not require. Multiple classes of legitimate bypass (no-space variants, command-substitution wrapping, env-var indirection) pass the splitter cleanly while bash still executes the malicious command.
3. **`.github/rulesets/main-protection.json:30-36`** lists four required checks (`lint-test`, `review`, `security-review`, `harness-validate`) and omits `evidence-gate`. The workflow exists and fires, but a developer or autopilot can merge a red `evidence-gate` PR because the ruleset doesn't require it.

Underlying meta-cause: the harness was written documentation-first, with code wiring done in batches. Several CLAUDE.md invariants were added before their enforcement was implemented, and the gap was not caught by validate.sh (which checks file existence and JSON validity but does not test whether documented invariants are actually enforced).

## Contributing factors

- **No "doc claim → code backing" audit**. Documentation makes assertions ("X is blocked by Y") and no script verifies Y exists or fires.
- **`validate.sh` was structural, not behavioral**. It confirms hooks exist on disk; it never executes them against red-team inputs.
- **The hook framework lacked a PreToolUse:Edit / PreToolUse:Write protection on constitution-class files**. The existing `pre-write-secret-scan.sh` was authored for secret-file protection only; the constitution-protection use case was added in docs but never to the hook body.
- **Single-author code review on the security-critical paths**. With no second pair of eyes on `pre-bash-guard.sh`'s regex set, bypass classes that obvious-to-an-attacker were not caught.
- **The sandbox config `permissions.sandbox.enabled: false`** was set during initial development for convenience and never flipped on for production use.

## What went well

- The audit caught the gap **before** the harness was used in production for any third-party project.
- The multi-agent audit format (five independent angles in parallel) surfaced findings none of the individual agents would have caught on their own — security agent found the `$()` bypass; verifier agent found the missing required-check; architect agent found the contradiction between the documented OQ-aging and its absence in routines.
- The harness's own discipline (specs / plans / evidence-gate) is being used to fix the harness — the meta-process works.

## What went poorly

- The harness shipped v2.0.0 with documentation theater on its most security-critical claims.
- `validate.sh`'s 14 categories did not include "behavior tests for documented invariants" — a deep gap in the validator itself.
- The `disableBypassPermissionsMode: "disable"` string-vs-boolean trap exists in Claude Code itself; the harness correctly uses the string form, but documents the trap in CLAUDE.md only — the regex check in `validate.sh` catches the trap, which is good, but the parallel sandbox-disabled config was not caught by any similar gate.
- No incident memory was filed previously for "the harness claims protections it doesn't have" — this is the first.

## Action items

All action items are tracked as acceptance criteria in `specs/active/001-harness-hardening.md`. Cross-reference:

- [ ] @shravan-qyndex, due 2026-06-04 — Spec 001 AC-1 (constitution write-protection in hook + settings deny list)
- [ ] @shravan-qyndex, due 2026-06-04 — Spec 001 AC-2 (`pre-bash-guard` bypass test suite + fixes)
- [ ] @shravan-qyndex, due 2026-06-04 — Spec 001 AC-3 (evidence-gate added to required checks)
- [ ] @shravan-qyndex, due 2026-06-04 — Spec 001 AC-4 (sandbox enabled in `permissionMode: auto` contexts)
- [ ] @shravan-qyndex, due 2026-06-11 — Spec 001 AC-24 (every documented security invariant has a passing test in `.claude/scripts/test/security-invariants.sh`)
- [ ] @shravan-qyndex, due 2026-06-11 — Spec 001 AC-25 (`.claude/scripts/audit-doc-claims.sh` scans for assertion patterns and verifies the named gate exists)

## Lessons for the agent

> **Documentation that claims a protection without backing code is a vulnerability, not a safeguard. Every "blocked by", "enforced by", "required by", or "gated by" in `.claude/CLAUDE.md`, `CLAUDE.md`, or `docs/**`must point to a script, hook, workflow, or ruleset that exists on disk and is exercised by`validate.sh` against a red-team input. If you cannot point to the code, the claim is theater — remove the claim or ship the code, but never both states at once.\*\*

This rule applies double for security claims. A misaligned or compromised agent reads CLAUDE.md the same way an operator does — if the doc says the constitution is protected, the agent may believe it and behave accordingly, but an adversary who reads the actual hook code will exploit the gap. Documentation theater is worse than honest absence because it creates false confidence.

This entry is linked from `.claude/memory/MEMORY.md`.
