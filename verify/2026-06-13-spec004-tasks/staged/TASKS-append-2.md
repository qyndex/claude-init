# Staged TASKS.md append (round 2) — spec 004 findings discovered while remediating

`tasks/TASKS.md` is constitution-class — operator pastes. Add before `## Spec 003 critical path`.

These surfaced while making the live E2E good-path PR green. T-132..T-136 are
fixed (writable parts applied, guarded parts staged). The tasks below are
NEWLY-FOUND scope from the same run and remain OPEN.

```
- [ ] T-137  | spec:004  | phase:1  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: no  | est: 5m
  summary: lint.sh shellcheck (-S warning, full repo) fails on 132 SC2164 + ~68 other warning-level diagnostics across .claude/scripts/*.sh (SC2034/2154/2010/2046/2155/2188/2043/1010/2319...) — broader than the T-132 hook scope; triage real bugs vs noise, fix or justify, narrow .shellcheckrc to only the defensible codes
  files: .claude/scripts/*.sh, .shellcheckrc
  accept: bash .claude/scripts/lint.sh
  owner: implementer

- [ ] T-138  | spec:004  | phase:6  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps: T-134  | parallel: no  | est: 4m
  summary: check-daily-batch can never go green on a fresh repo because daily-batch.yml itself was unrunnable (FINDING-16, now fixed) AND its child gates (codeql/semgrep/lighthouse/osv) must pass once; verify a full daily-batch run is green on a clean scaffold, else the merge-gate first-run path is the only way through
  files: .github/workflows/daily-batch.yml
  accept: gh workflow run daily-batch.yml && echo dispatched
  owner: implementer

- [ ] T-139  | spec:004  | phase:7  | priority: medium  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 3m
  summary: setup.sh / harness-doctor should check the Claude GitHub App is installed (FINDING-15) — claude-review/security-review/anti-slop can never pass without it regardless of credential type; today the only signal is a 401 deep in the action log
  files: .claude/scripts/setup.sh, .claude/scripts/harness-doctor.sh
  accept: grep -q 'install-github-app\|apps/claude' .claude/scripts/setup.sh
  owner: implementer
```
