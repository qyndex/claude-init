## Summary

<Concrete problem and resulting behavior. Use .claude/skills/pr-body/SKILL.md before publishing.>

## Spec / Plan

- Spec: specs/active/<NNN>-<slug>.md
- Plan: plans/active/<NNN>-<slug>.md

## What changed

- <bullets — what shipped, not how>

## Evidence Bundle

> Round 10 C: paste the output of `bash .claude/scripts/collect-evidence.sh <spec-id>`
> here for EVERY applicable spec, alongside the summary. `/ship` uses the pr-body
> skill to compose the complete body and publish it with `--body-file`.
> The `evidence-gate` required check parses this block and BLOCKS merge if any AC is UNPROVEN.

- Acceptance criteria: <N/N proven> (table from pr-body.md)
- Smoke test: exit codes from `verify/<date>-<feature>/smoke.log`
- Screenshots: `verify/<date>-<feature>/screenshots/AC-*.png` (committed)
- Video + trace: CI artifact `verify-evidence` (heavy binaries gitignored)
- API traces: `verify/<date>-<feature>/traces/*.json`
- Coverage: line/branch + delta
- Verdict: <actual collector result; do not claim PASS before verification>

## Tests

- Unit: <count> added / <count> total (red→green ledger under `verify/<date>/T-*/`)
- Integration: <added/total>
- E2E: every spec AC proven via `spec-match.sh` — see `verify/<date>-<feature>/EVIDENCE.md`

## Risk + rollback

- Risk: <one line>
- Rollback: `git revert <sha>` is safe / requires migration revert (see PLAYBOOK)

## Reviewer checklist

- [ ] Acceptance criteria from the spec are covered
- [ ] Tests added for new behavior
- [ ] No new TODO/FIXME without a tracked task
- [ ] Lint + typecheck pass
- [ ] Security review clean (if auth/data/network/deps touched)
- [ ] Docs and CHANGELOG updated

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
