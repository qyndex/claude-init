---
id: 003
slug: audit-round2-remediation
status: shipped
owner: "@claude"
human_owner: "@shravan"
created: 2026-05-29
updated: 2026-05-29
supersedes:
superseded_by:
complexity: L
objective: KR-2026Q3-HARNESS-FACTORY-FITNESS
initiative: harness-factory-readiness
service_tier: T1
feedback_refs: []
github_issue:
---

# Spec 003: Audit Round-2 Remediation — Delivery-pipeline integrity, gate enforceability, supply-chain hardening

> Closes every finding from the 2026-05-29 (second) five-agent audit that was NOT already fixed inline. The round-1 fixes (CI job-name deadlock, version-agnostic model gate, graphify typo, broken skill refs, dead PII regex, constitution-guard path bypass + bypass logging) landed directly. This spec covers the items that were either (a) blocked by the auto-mode self-modification classifier, (b) structurally larger than a one-line fix, or (c) deferred for an explicit decision. Companion artifact: the audit transcript embedded in the 2026-05-29 session.

## Problem statement

The round-2 audit confirmed the harness is structurally strong but found three classes of issue that survive round-1's inline fixes and would hinder autonomous multi-month delivery:

1. **Gates that don't actually gate.** `verify.sh` honors agent-settable `SKIP_*` env vars in the autonomous loop, so the TDD-ledger / coverage / assert-density gates can be silently disarmed by the very agent they constrain. `evidence-gate.yml` falls through to trusting PR-body prose when no `evidence.json` is committed, so an agent that writes its own PR body can self-assert "Verdict: PASS". Both defeat constitution §VII ("if there's no artifact, it didn't happen") in exactly the unattended context it is meant to protect.

2. **A safety story that rests on inert config.** The `permissions.sandbox` block in `settings.json` is not a recognized settings-schema key — Claude Code silently ignores it — so the documented "fresh sandbox → Auto Mode" containment (CLAUDE.md §X/§XI) is not enforced by this file. Separately, the `filesystem` MCP server is scoped to the repo root and reads/writes through its own access path, which is NOT constrained by the settings `deny: Read(**/*.pem)` list — so the secret deny-list is bypassable via `mcp__filesystem__read_text_file`.

3. **Permission and supply-chain gaps + lifecycle drift.** Bare `Edit` is unscoped (re-opening the hole the round-1 `Write` narrowing closed); the narrowed `Write` list omits legitimate autonomous-write targets (`OVERNIGHT_REPORT.md`, `initiatives/**`, `.claude/rules/**`, `roadmap.md`, `OKRs.md`) so the overnight loop hits write denials; the deny-list misses common credential formats (`.npmrc`, `.netrc`, `.git-credentials`, `*.pfx`, `*.p12`, `*.tfstate` read, `*.kubeconfig`, `.pypirc`, `.docker/config.json`); the two `alwaysLoad` MCP servers (filesystem, git) are unpinned; CI review workflows pin a stale model (`opus-4-7`); `worktree.baseRef: "head"` is not a valid schema enum value (silently dropped, breaking bg-isolation assumptions); and completed specs 001/002 remain `status: approved` in `specs/active/` where an autonomous agent reads them as live work.

Left unremediated, an autonomous agent processing untrusted input (web/issue/MCP content — explicitly in-scope per §II) has a realistic prompt-injection → unverified-merge or secret-exfiltration path, and the multi-month loop will both hit spurious write denials and slowly drift on stale config.

## Goals

In scope:

- **Phase 1 (Gate enforceability)**: make `verify.sh` refuse `SKIP_*` unless an operator marker file is present + always log the active SKIP set; re-run the TDD-ledger check server-side in CI where the agent cannot set env; make `evidence.json` mandatory in `evidence-gate.yml` (stop trusting PR-body prose).
- **Phase 2 (Permission hardening)**: scope bare `Edit` to the same directories as `Write`; add the legitimate autonomous-write targets; close the credential deny-list gaps; harmonize Read vs Write deny sets.
- **Phase 3 (Sandbox + MCP containment)**: document that `permissions.sandbox` is inert and wire sandboxing through the supported runtime mechanism (or remove the misleading block + comment); scope the `filesystem` MCP server root to exclude secret paths; pin the `filesystem` and `git` MCP servers.
- **Phase 4 (Supply-chain + config drift)**: bump CI workflow `model:` pins to `claude-opus-4-8` + extend the consistency check to cover workflow model fields; fix/remove `worktree.baseRef` + `worktree.symlinkDirectories` schema violations; add a `validate.sh` ruleset↔job-name coverage check (the root cause that let the round-1 CI deadlock ship).
- **Phase 5 (Lifecycle correctness)**: advance specs 001 & 002 to `status: shipped` and add automatic spec-status advancement when a spec's last task goes `[x]`; tighten `stale-spec-check.yml` to also flag 100%-complete `approved` specs as ready-to-archive.
- **Phase 6 (Verification + exit)**: full `validate.sh` clean + paired red/green TDD evidence per task + REPORT.md.

## Non-goals

- Aggressively moving `npx`/`uvx`/`make`/`just`/`curl` to the `ask` list — the round-1 decision was explicitly "fix safe wins only," because those entries are needed for legitimate autonomous builds and gating them adds operator friction contrary to the "minimal intervention" goal. Documented as accepted residual risk, not closed here.
- Replacing the BYO deploy stub with a real pipeline (intentional, documented in docs/DEPLOY-INTEGRATION.md).
- Re-litigating any round-1 inline fix.

## User stories

- **As an operator running the overnight loop**, I want the verification gates to be un-bypassable by the agent, so that a green PR genuinely means the ACs were proven — not self-asserted.
- **As a security owner**, I want the secret deny-list to actually cover the file the agent could read, and the `Edit` tool scoped, so an injected instruction cannot exfiltrate `.npmrc`/`.git-credentials` or rewrite an arbitrary file.
- **As an operator months into a project**, I want completed specs to leave `specs/active/` automatically, so the agent never re-engages finished work, and stale config (model pins, schema-invalid keys) to be caught by `validate.sh`.

## Acceptance criteria

### Phase 1 — Gate enforceability

1. **AC-1 (SKIP\_\* requires operator marker)**: `verify.sh` honors any `SKIP_*` env var ONLY when `.claude/state/allow-skip-gates` exists (operator-created, gitignored). Without the marker, a set `SKIP_*` is ignored and the gate runs. Verified by: `SKIP_TDD_LEDGER=1 bash .claude/scripts/verify.sh` with no marker still runs the ledger check (fails if ledger absent); with the marker present it skips. Test artifact: `verify/2026-05-29-003/T-AC-1-skip-marker.log`.

2. **AC-2 (SKIP\_\* is logged)**: `verify.sh` prints the active `SKIP_*` set to stdout AND appends it to the evidence bundle on every run, so a skipped gate is visible at PR review. Verified by: `SKIP_COVERAGE=1 ... bash verify.sh` output contains a line listing `SKIP_COVERAGE`. Test artifact: `verify/2026-05-29-003/T-AC-2-skip-log.log`.

3. **AC-3 (server-side TDD-ledger re-check)**: a step **added to the existing `harness-validate.yml` job** (already in the required set) re-runs the TDD-ledger check for `[x]` tasks server-side, where the agent cannot set `SKIP_*`. Per R-1, the step only checks tasks whose `verify/` evidence is git-tracked, and warns (not fails) on missing-but-untracked. Verified by: a PR marking a tracked task `[x]` without `red.log`+`green.log` fails the harness-validate check. Test artifact: `verify/2026-05-29-003/T-AC-3-server-ledger.log`.

4. **AC-4 (evidence.json mandatory)**: `evidence-gate.yml` fails when `find verify -name evidence.json` is empty (no fallback to PR-body prose), and drives the verdict purely from the committed JSON (`ac_unproven == 0`, `smoke_exit_max == 0`, `verdict == PASS`). The PR-body grep is reduced to a presentation check. Verified by: a PR with a `## Evidence Bundle / Verdict: PASS` body but NO committed `evidence.json` fails the gate. Test artifact: `verify/2026-05-29-003/T-AC-4-evidence-mandatory.log`.

### Phase 2 — Permission hardening

5. **AC-5 (Edit scoped)**: `settings.json` replaces bare `"Edit"` with `Edit(<dir>/**)` entries matching the `Write` allow set (src, tests, specs, plans, tasks, docs, verify, .swarms, initiatives, .claude/memory, .claude/memory.proposed, .claude/state, .claude/rules + the named root files). Verified by: `jq -e '.permissions.allow | index("Edit") | not' .claude/settings.json` is true (no bare Edit) AND `jq '.permissions.allow[] | select(startswith("Edit("))' | wc -l` ≥ 13.

6. **AC-6 (legit Write targets present)**: `settings.json` allow includes `Write(initiatives/**)`, `Write(.claude/rules/**)`, `Write(OVERNIGHT_REPORT.md)`, `Write(ADOPTION-REPORT.md)`, `Write(roadmap.md)`, `Write(OKRs.md)`; `additionalDirectories` includes `./initiatives`. Verified by: `jq '.permissions.allow' .claude/settings.json` contains all six entries AND `jq '.permissions.additionalDirectories' contains `./initiatives`. Test artifact: `verify/2026-05-29-003/T-AC-6-write-targets.log`.

7. **AC-7 (credential deny-list closed)**: both Read and Write deny lists include `**/*.p12`, `**/*.pfx`, `**/.npmrc`, `**/.netrc`, `**/_netrc`, `**/.git-credentials`, `**/*.kdbx`, `**/.pypirc`, `**/*.kubeconfig`, `**/kubeconfig`, `**/.docker/config.json`; Read deny adds `**/*.tfstate` and `**/.aws/credentials` (Write already had `.tfstate`). Verified by: a deny-coverage fixture (`verify/2026-05-29-003/T-AC-7-deny-fixtures.sh`) asserts each pattern is present in BOTH lists. `validate.sh` security-invariant check extended to assert these.

### Phase 3 — Sandbox + MCP containment

8. **AC-8 (real runtime sandbox)**: the inert `permissions.sandbox` block is removed from `settings.json`; the actual runtime-sandbox mechanism (Claude Code `--sandbox` launch flag / OS-level sandbox) is documented in `docs/AUTOPILOT.md` and applied in the overnight routine (`.claude/routines/overnight-build.yml`); `CLAUDE.md §X/§XI` are corrected to reference the runtime mechanism instead of claiming settings.json enforces the sandbox. Verified by: `jq -e '.permissions.sandbox' .claude/settings.json` returns null/absent; `grep -q 'sandbox' docs/AUTOPILOT.md` and the overnight routine references the flag; no doc claims settings.json sandboxes the run. Test artifact: `verify/2026-05-29-003/T-AC-8-runtime-sandbox.log`.

9. **AC-9 (filesystem MCP scoped away from secrets)**: the `filesystem` MCP server `args` root is scoped so it cannot read `.env*` / secret paths (either a subdirectory root, or the server's own deny mechanism), OR `CLAUDE.md §X` documents that the filesystem MCP bypasses the settings deny-list and the mitigation. Verified by: inspection that the filesystem server root + a documented note exist. Test artifact: `verify/2026-05-29-003/T-AC-9-fs-mcp-scope.log`.

10. **AC-10 (alwaysLoad MCP servers pinned)**: `filesystem` and `git` MCP server install args carry an explicit version pin (not a bare package name). Verified by: `validate.sh` MCP check reports zero bare-name args for `alwaysLoad: true` servers. Test artifact: `verify/2026-05-29-003/T-AC-10-mcp-pin.log`.

### Phase 4 — Supply-chain + config drift

11. **AC-11 (CI workflow model pins current)**: `claude-review.yml` and `claude-security.yml` `model:` fields are `claude-opus-4-8` (matching constitution §V). Verified by: `grep -rE 'model:\s*claude-opus-4-7' .github/workflows/` returns zero matches.

12. **AC-12 (model consistency covers workflows)**: `check-model-consistency.sh` (or `check-doc-consistency.sh`) extended to flag literal `opus-4-7` / `Opus 4.7` references in `.github/workflows/**` and `docs/**` so a future bump can't strand them. Verified by: a synthetic workflow pinning `opus-4-7` fails the check.

13. **AC-13 (worktree schema valid)**: `worktree.baseRef` is set to a schema-valid value (or removed) and `worktree.symlinkDirectories` is removed or moved to the supported location, so neither is silently dropped. Verified by: zero schema diagnostics on the `worktree` block; `validate.sh` settings check passes.

14. **AC-14 (ruleset↔job coverage check)**: `validate.sh` adds a category that parses every `required_status_checks` context in `.github/rulesets/main-protection.json` and confirms each maps to a job that (a) exists in `.github/workflows/*`, (b) triggers on `pull_request` to main, and (c) has no `paths:` filter or unconditional-skip `if:` that would leave it pending-forever. Verified by: a synthetic ruleset context with no matching job fails `validate.sh`. This is the root-cause check that would have caught the round-1 deadlock. Test artifact: `verify/2026-05-29-003/T-AC-14-ruleset-coverage.log`.

### Phase 5 — Lifecycle correctness

15. **AC-15 (completed specs shipped)**: specs `001-harness-hardening.md` and `002-audit-remediation.md` frontmatter `status:` advanced to `shipped` (all their tasks are `[x]`/`[s]`). Verified by: `grep -c 'status: shipped' specs/active/001-harness-hardening.md specs/active/002-audit-remediation.md` returns 2 (or they are archived).

16. **AC-16 (auto spec-status advancement)**: a mechanism (Stop hook, `/ship` step, or a `spec-status-sync.sh` invoked by an existing hook) flips a spec's `status:` to `shipped` when its last referencing task transitions to `[x]`. Verified by: a synthetic spec with one task — marking the task `[x]` then running the sync advances the spec to `shipped`. Test artifact: `verify/2026-05-29-003/T-AC-16-status-sync.log`.

17. **AC-17 (stale-spec check flags ready-to-archive)**: `stale-spec-check.yml` additionally flags `status: approved` specs whose referencing tasks are 100% `[x]`/`[s]` as "ready to archive," so the quarterly archiver is not the only safety net. Verified by: a fixture with an all-tasks-done approved spec is flagged.

### Phase 6 — Verification + exit

18. **AC-18 (full clean)**: `bash .claude/scripts/validate.sh` exits 0 and `/harness-doctor` reports no errors after all phases. Every task in this spec has paired `verify/2026-05-29-003/T-<id>/red.log` + `green.log`. A `verify/2026-05-29-003/REPORT.md` summarizes each AC with PASS evidence.

## Constraints

- **Self-modification of `settings.json` requires operator approval.** The Auto-Mode classifier (correctly) blocks an agent from widening/altering its own permission allow/deny lists. Phase 2/3 settings edits must be applied with the operator present/approving, OR the operator applies the diff manually from a generated patch. The spec/tasks must generate the exact diff and surface it; they must not attempt to bypass the classifier.
- Constitution-class files (`.claude/CLAUDE.md`, `settings.json`, `hooks/*`, `.github/workflows/*`, rulesets) are write-blocked by `pre-edit-constitution-guard.sh`. Edits to those use the documented operator escape hatch (`FORCE_CONSTITUTION_EDIT=1`) with the bypass now logged — the operator runs the session; the harness must not self-set the variable.
- Surgical changes only (constitution §I.3): every changed line traces to an AC here.
- No regression to any round-1 fix or any spec-001/002 invariant.

## Open questions (RESOLVED 2026-05-29 by @shravan)

- `[RESOLVED OQ-1]` AC-3 server-side ledger → **fold into the existing `harness-validate` job** (no new required check; avoids another ruleset-coverage burden).
- `[RESOLVED OQ-2]` AC-8 sandbox → **option (a): wire a real runtime sandbox**. Remove the inert `permissions.sandbox` block; document the actual OS-sandbox / launch-flag mechanism in `docs/AUTOPILOT.md` + the overnight routine; correct `CLAUDE.md §X/§XI` to point at the runtime mechanism rather than claiming settings.json enforces it.
- `[RESOLVED OQ-3]` AC-16 status-sync trigger → **`spec-status-sync.sh` called from the existing `post-write-roadmap.sh` PostToolUse:Write hook** when `tasks/TASKS.md` changes (mirrors existing roadmap-state derivation; no new hook registration).

## Risks

- **R-1**: server-side ledger re-check (AC-3) could false-fail on tasks whose evidence is legitimately gitignored. Mitigation: re-check only tasks whose `verify/` dir is tracked; warn (not fail) on missing-but-untracked.
- **R-2**: scoping `Edit` (AC-5) could block a legitimate edit to a root config the agent occasionally touches. Mitigation: mirror the Write set exactly + the named root files; the operator escape hatch covers constitution-class edits.
- **R-3**: making `evidence.json` mandatory (AC-4) could block merges for change types that have no runnable ACs (pure-doc PRs). Mitigation: allow a `verify/<date>/no-ac.json` sentinel (`{"verdict":"PASS","ac_unproven":[],"smoke_exit_max":0,"reason":"docs-only"}`) so doc PRs produce a real artifact rather than relying on prose.
