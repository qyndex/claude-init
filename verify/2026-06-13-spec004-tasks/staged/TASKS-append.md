# Staged TASKS.md append — spec 004 (live-E2E CI findings)

`tasks/TASKS.md` is constitution-class (pre-edit-constitution-guard.sh:102) — agent
writes are denied by design. Operator: paste the block below into
`tasks/TASKS.md` immediately BEFORE the `## Spec 003 critical path` line, then run
`bash .claude/scripts/validate.sh`.

```
- [ ] T-132  | spec:004  | phase:1  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: no  | est: 5m
  summary: Make shipped hooks pass the harness-validate/CI shellcheck-on-hooks gate (or declare a committed baseline) — ~44 SC1083/SC2034/SC2164/SC2012/SC2221 diagnostics; live-E2E found CI red on claude-init main while validate.sh is green
  files: .claude/hooks/*.sh, .github/workflows/harness-validate.yml, .github/workflows/ci.yml
  accept: shellcheck --format=gcc .claude/hooks/*.sh
  owner: implementer

- [ ] T-133  | spec:004  | phase:2  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 5m
  summary: Triage silent-failure-audit 222 unjustified of 1059 — justify legitimate swallows, fix real ones, or commit a baseline + burn-down; gate currently exits 1 on claude-init main and every adopter's first push
  files: .claude/scripts/lint-silent-failures.sh, .claude/state/silent-failure-audit.json
  accept: bash .claude/scripts/lint-silent-failures.sh
  owner: implementer

- [ ] T-134  | spec:004  | phase:3  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 5m
  summary: Fix merge-gate check-daily-batch first-run on a fresh repo + age window using first-commit date (git-archive adoption leaks old timestamps so a today-created repo reads as weeks old)
  files: .github/workflows/merge-gate.yml
  accept: grep -q 'git log --reverse' .github/workflows/merge-gate.yml && echo "review age-calc source"
  owner: implementer

- [ ] T-135  | spec:004  | phase:4  | priority: medium  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 4m
  summary: Ship a commitlint.config aligning subject-case with §VI commit protocol (default conventional config rejects leading-capital/acronym subjects the harness's own commits use)
  files: commitlint.config.js, .github/workflows/commitlint.yml
  accept: test -f commitlint.config.js || test -f commitlint.config.mjs
  owner: implementer

- [ ] T-136  | spec:004  | phase:5  | priority: medium  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 4m
  summary: Stop doc-claims-audit false-positiving on docs/factory-history quoted-JSON permissionDecisionReason examples (gates that DO exist flagged ORPHAN); decide whether factory-history ships to greenfield at all
  files: .claude/scripts/audit-doc-claims.sh, .claude/scripts/setup.sh
  accept: bash .claude/scripts/audit-doc-claims.sh
  owner: implementer
```
