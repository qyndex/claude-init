# claw-code Audit — 2026-05-28

**Repo:** https://github.com/ultraworkers/claw-code  
**Audited by:** researcher agent  
**Audited on:** 2026-05-28  
**Stars (at audit):** ~193k (Trendshift, 2026-05)

---

## Repo summary

claw-code is a Rust CLI runtime (9-crate workspace) that reimplements a Claude-Code-shaped agentic harness with multi-provider support (Anthropic, OpenAI-compat, xAI, DashScope). Its philosophy ("clawability") centres on autonomous, human-directed agent fleets operated via Discord rather than a terminal — humans set direction, agents do the labour. It is ~8 weeks old at time of audit (origin story: ported Python overnight on 2026-03-31 from an exposed source, then rewritten in Rust). The `.claude/` folder contains only a `sessions/` directory; the project's contribution to Claude Code-style _harness_ patterns lives primarily in its docs/, scripts/, and ROADMAP.md.

---

## ADOPT

- **Explicit worker lifecycle state machine** (`ROADMAP.md` §Phase 1: "spawning → trust_required → ready_for_prompt → prompt_accepted → running → finished/failed")  
  WHY: claude-init's parallel swarm tracks streams via `claw agents` output and coordinator YAML, but has no typed lifecycle states for background workers. A state-machine enum in `.swarms/coordinator/` would make phantom-completion bugs (parallel lanes writing to each other) detectable at the harness layer rather than discovered post-hoc.  
  INTEGRATION: add a `worker-state.json` schema (mirroring `.claw/worker-state.json`) per worktree under `.swarms/streams/<id>/state.json`; extend `post-bash-log.sh` to write state transitions; teach the coordinator agent to gate prompt dispatch on `ready_for_prompt` rather than "session spawned".

- **Typed lane events with structured error envelopes** (`docs/g004-events-reports-contract.md`)  
  WHY: claude-init's hooks emit free-text logs (`post-bash-log.sh`). claw-code's contract defines `lane.started / lane.blocked / lane.red / lane.green / lane.finished` plus a typed error envelope (`error.kind`, `error.operation`, `error.retryable`, contextual hints). This would make `requeue-failed.sh` and the coordinator's merge-decision logic reliably parseable and would allow the evidence-gate to consume structured events instead of scraping log files.  
  INTEGRATION: extend `post-bash-log.sh` and `subagent-stop.sh` to emit JSONL lane events to `.swarms/events/<stream-id>.jsonl`; write a thin `lane-event-schema.json` under `.swarms/templates/`; the coordinator reads from events, not from session stdout.

- **Workspace-fingerprinted session isolation** (`docs/g010-clone-disambiguation-metadata.md`)  
  WHY: claude-init uses worktrees (`.swarms/streams/<id>/`) but does not partition session state by workspace fingerprint. The claw-code approach (FNV-1a digest of canonical workspace path → `.claw/sessions/<fingerprint>/`) prevents phantom completions across parallel worktrees. This is a clean, low-LOC fix for a real bug class.  
  INTEGRATION: update `session-heartbeat.sh` to compute `WORKSPACE_FP=$(printf "%s" "$(pwd -P)" | md5 | cut -c1-16)` and write session references under `.claude/sessions/$WORKSPACE_FP/` rather than a flat path.

- **Branch freshness preflight before test execution** (`docs/g005-branch-recovery-verification-map.md`, ROADMAP §"Branch freshness validation")  
  WHY: claude-init's `verify.sh` runs tests without first checking whether the current branch is stale against main. claw-code emits a structured `branch.stale_against_main` event and blocks broad test sweeps on diverged branches. This would prevent the false-regression class of failures that waste overnight-build cycles.  
  INTEGRATION: add a `branch-freshness.sh` pre-verify check: `git fetch --quiet && git merge-base --is-ancestor HEAD origin/main || echo '{"event":"branch.stale_against_main"}'`. Wire it as the first step in `verify.sh` (before the stack-detection block). Respect `SKIP_BRANCH_CHECK=1` for CI.

- **Anti-slop triage gate for AI-generated PRs** (`docs/anti-slop-triage.md`)  
  WHY: claude-init's `evidence-gate.yml` blocks merge on unproven ACs, but has no gate against mechanically-generated, unfocused, or unverifiable contributions — a problem as the harness is adopted by teams where agents themselves open PRs. claw-code's eight-class triage (actionable-bug, actionable-docs, duplicate, generated-slop, spam, security-sensitive, not-reproducible, externally-blocked) is a clean, prompt-engineerable checklist that could live as a `reviewer` agent instruction.  
  INTEGRATION: add `.claude/agents/quality/anti-slop-reviewer.md` that runs the eight-class triage on every PR body and reports classification + rationale. Wire to `pr-review` CI step.

- **`/doctor` preflight diagnostics** (`USAGE.md`, `claw doctor --output-format json`)  
  WHY: claude-init's `/harness-doctor` is a bash script with string output. claw-code's `doctor` command has a `--output-format json` mode for machine-readable preflight results. Adding JSON output to `harness-doctor` would let CI ingest health-check results as structured evidence and block on specific failed checks rather than on non-zero exit alone.  
  INTEGRATION: extend `validate.sh` with a `--json` flag that writes a report to `verify/doctor-<date>.json`; add the report as an artifact in `harness-validate.yml`.

---

## REJECT

- **Discord as the human interface** (`PHILOSOPHY.md`)  
  CONFLICT: claude-init's operator interface is the terminal, spec files, and CI. Discord integration would add an always-on external channel dependency, violate the "no HTTP endpoints for worker state" principle that claw-code itself endorses for internal use, and introduce a social-platform availability risk. The harness is designed to be self-contained and offline-capable. Reject; discord integration can be a user-side plugin if desired.

- **Multi-provider routing (xAI, DashScope, Ollama, OpenRouter)** (`USAGE.md` §Provider Matrix)  
  CONFLICT: claude-init pins all agents to specific Anthropic model IDs in frontmatter (`model: claude-sonnet-4-6`, etc.). Provider-routing abstraction would break the Opus/Sonnet/Haiku routing table (CLAUDE.md §V) and introduce non-determinism in model assignment — the exact failure mode the tiered model table prevents. The harness is Anthropic-first by deliberate design. Reject; provider routing is a runtime concern outside harness scope.

- **`.omx/` and `oh-my-codex` plugin layer** (repo root `.omx/` directory, PHILOSOPHY.md)  
  CONFLICT: OmX is claw-code's proprietary orchestration layer (separate project). Importing it would create an undeclared transitive dependency on an unversioned external tool and violate the "version-pinned, deferred via Tool Search" MCP server model. claude-init already has a richer orchestration layer (swarm coordinator, skills system, handoff contracts). Reject as redundant and unsafe.

- **File-based polling as the sole observability contract** (ROADMAP §"file-based polling over HTTP endpoints")  
  CONFLICT: claw-code deliberately avoids HTTP because it runs as an opencode plugin without HTTP route ownership. claude-init has no such constraint. Adopting file-poll-only would regress from the OTEL/Langfuse observability layer (`docs/OBSERVABILITY.md`) that already provides structured traces. Reject the constraint; adopt the _structured events_ idea (above) without the file-poll limitation.

- **Rust runtime** (`rust/` workspace)  
  CONFLICT: claude-init is a shell/YAML/Markdown harness — deliberately stack-agnostic. Importing or depending on the Rust binary is out of scope. The valuable ideas (state machines, typed events, session isolation) are patterns that can be implemented in bash/JSON/YAML within the existing harness. Reject the binary; adopt the patterns.

---

## MAYBE

- **`/teleport` — navigate to files or symbols by name** (`USAGE.md §Advanced Commands`)  
  The current harness uses `Graphify MCP` for cross-module navigation. `/teleport` is described as a REPL command but its implementation (likely a fuzzy-finder wrapper over `grep`/`ripgrep`) may offer a lighter-weight in-session alternative for smaller repos. Needs inspection of the actual Rust implementation before deciding.

- **`/ultraplan` — multi-step reasoning for complex tasks** (`USAGE.md §Advanced Commands`)  
  Name suggests a planning mode distinct from the harness's `/plan`. Could map to a skill. Evidence thin — no spec for what it actually does. Flag for follow-up if the Rust source for `commands/ultraplan` is readable.

- **Approval-token and policy-block contract** (`docs/g004-events-reports-contract.md §Approval-Token and Policy-Block Contract`)  
  The idea — structured approval tokens with actor scope, expiry, and use count replacing prose "approved" — is interesting for the evidence-gate. Currently `collect-evidence.sh` captures AC checklists but not typed approvals. Worth a small prototype to see if it improves the evidence-gate PR body. Tentative.

- **Negative-evidence as first-class in reports** (`docs/g004-events-reports-contract.md §Report Schema v1`)  
  claw-code distinguishes `not observed` from `checked and absent` from `redacted`. This maps naturally to claude-init's TDD ledger (absence of a green.log is ambiguous — was the test not run, or was it run and skipped?). Could sharpen the TDD ledger schema. Tentative.

- **`roadmap-check-ids.sh` and `roadmap-next-id.sh`** (`scripts/`)  
  Lightweight ID-management scripts for roadmap items. claude-init has `tasks/TASKS.md` but no auto-increment for T-IDs. These scripts are small and self-contained; worth reading before rejecting.

---

## Verdict

claw-code is a **different paradigm** — it is a compiled runtime with a Discord-native, fleet-autonomous philosophy — but its _specification documents_ (roadmap, events contract, branch recovery map, session hygiene map) contain six concrete, implementable patterns that claude-init currently lacks or handles less rigorously. The Rust binary itself and the multi-provider routing are out of scope; the architectural patterns extracted above are directly adoptable.

---

## Citations

1. https://github.com/ultraworkers/claw-code (repo root, accessed 2026-05-28)
2. https://github.com/ultraworkers/claw-code/blob/main/PHILOSOPHY.md (accessed 2026-05-28)
3. https://github.com/ultraworkers/claw-code/blob/main/USAGE.md (accessed 2026-05-28)
4. https://raw.githubusercontent.com/ultraworkers/claw-code/main/ROADMAP.md (accessed 2026-05-28)
5. https://raw.githubusercontent.com/ultraworkers/claw-code/main/docs/g004-events-reports-contract.md (accessed 2026-05-28)
6. https://raw.githubusercontent.com/ultraworkers/claw-code/main/docs/g005-branch-recovery-verification-map.md (accessed 2026-05-28)
7. https://raw.githubusercontent.com/ultraworkers/claw-code/main/docs/g010-clone-disambiguation-metadata.md (accessed 2026-05-28)
8. https://raw.githubusercontent.com/ultraworkers/claw-code/main/docs/g010-session-hygiene-verification-map.md (accessed 2026-05-28)
9. https://raw.githubusercontent.com/ultraworkers/claw-code/main/docs/anti-slop-triage.md (accessed 2026-05-28)
10. https://raw.githubusercontent.com/ultraworkers/claw-code/main/docs/g007-mcp-lifecycle-mapping.md (accessed 2026-05-28)
11. https://trendshift.io/repositories/24872 (star count, accessed 2026-05-28)
