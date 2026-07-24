---
name: 0004-autonomous-green-gated-merge
description: ADR-0004: Autonomous green-gated merge with zero-approval ruleset
status: accepted
created: 2026-07-24
metadata:
  type: decision
  status: proposed
---

# ADR-0004: Autonomous green-gated merge with zero-approval ruleset

- **Date**: 2026-07-24
- **Deciders**: operator (admin@qyndex.com), claude
- **Owners**: [@operator]
- **written_by**: operator+claude
- **source_session**: pid-99148
- **last_verified**: 2026-07-24
- **Context**: operator goal "work autonomously, auto-merge PR when all checks pass, update status, daily briefing with proof"
- **Tags**: ci,autonomy,merge,ruleset
- **subsystem**: ci

## Context

The operator asked for hands-off shipping: an agent that opens a PR, and — with no human in the loop — merges it once CI is green, then reconciles spec/task/initiative status and writes a proof-backed morning briefing. Two facts shaped the design:

1. The harness already had `.github/workflows/auto-merge.yml` (native `gh pr merge --auto`), but **nothing armed it** for normal branches, and `overnight-build.yml:204` told the agent "Never auto-merge" — a direct contradiction with the armed workflow.
2. The `main-protection` ruleset required `required_approving_review_count: 1` + `require_code_owner_review: true` + `required_signatures`. Those **block any agent self-merge** (a human CODEOWNER approval + GPG-signed commits are impossible for the agent).

Fully-autonomous merge and "require a human approval" are mutually exclusive.

## Decision

- **Drop the human approval gate, keep the checks gate.** The ruleset becomes `required_approving_review_count: 0`, `require_code_owner_review: false`, and `required_signatures` removed — but all **9 required status checks remain**. The agent's own `review` + `security-review` CI jobs ARE the review.
- **The merge is green-gated and fail-closed.** `autonomous-ship.sh` arms native `gh pr merge --auto` ONLY when every required check is green; it refuses (no merge) on any pending/failing/skipped/absent check, or if no live ruleset exists. There is deliberately **no force flag and no checks-bypass override**: "no green, no merge."
- **Server-side ruleset is the real gate.** The agent arming `--auto` is safe because GitHub still evaluates the ruleset's required checks; without a live ruleset, `--auto` would merge on empty checks, so the script refuses in that state.
- **Interactive safety preserved.** `gh pr merge` stays on the settings.json `ask` list; only the wrapper scripts are allowlisted. Human-driven sessions still prompt.

## Alternatives considered

- **Keep 1 approval, agent does everything else** — human clicks the final Approve. Safer but not the requested hands-off autonomy; rejected per operator choice "Drop human approval, keep checks."
- **Agent runs a bare `gh pr merge --squash` after polling checks** — removes the server-side ruleset gate and the interactive `ask` safety; a check flipping between poll and merge would slip through. Rejected: `--auto` lets GitHub hold the gate.
- **Two rulesets (agent branches 0-approval, others 1-approval)** — scoped autonomy. Rejected as more moving parts than needed for a single-maintainer harness repo.

## Consequences

- Positive: an agent can ship end-to-end on green CI with zero humans; the ruleset's 9 checks are the enforced quality bar.
- Negative: a human no longer reviews every merge — quality rests entirely on CI green + the agent's own reviewer/security jobs. If a required check is missing or misconfigured, the gate weakens silently (mitigated: `autonomous-ship.sh` refuses when zero checks report).
- Negative: `required_signatures` removed → merges are unsigned. Re-add only if agent/CI commits are signed.
- Neutral: `reconcile-shipped.sh` + `daily-briefing.sh` make every shipped claim carry a proof artifact (evidence verdict / TDD ledger), so the loss of human review is partly offset by machine-checkable proof.

## Re-verification triggers

- A linked spec ships materially different behavior than what this ADR assumed.
- An incident touches the `ci` subsystem (e.g. a bad merge reaches main).
- GitHub changes ruleset/`--auto` semantics.
- 12 months have elapsed since `last_verified:`.

## References

- Spec: specs/active/005-traceability-and-decision-harvest.md (follow-up gap-closure)
- Scripts: .claude/scripts/autonomous-ship.sh, reconcile-shipped.sh, daily-briefing.sh
- Patches: .claude/memory.proposed/patches/AUTO-01..05
- Ruleset: .github/rulesets/main-protection.json
- Related ADRs: ADR-0002 (evidence-based verification gates), ADR-0003 (TASKS.md sole authority)
