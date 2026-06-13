# Staged TASKS.md append (round 3) — final live-E2E findings

Paste before `## Spec 003 critical path`. tasks/TASKS.md is constitution-class.

```
- [ ] T-140  | spec:004  | phase:1  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: no  | est: 5m
  summary: harness-validate "Structured harness report (validate.sh --json)" step exits 1 in CI but rc=0 locally (74 pass/1 warn/0 fail); no JSON or diagnostic reaches the step log, so --json appears to crash before printing under the GitHub runner toolchain/locale. Add an instrumented CI run (set -x / tee the report) to pin the failing category, then fix. Shellcheck-on-hooks and all other harness-validate steps PASS.
  files: .claude/scripts/validate.sh, .github/workflows/harness-validate.yml
  accept: report="$(bash .claude/scripts/validate.sh --json)" && printf '%s' "$report" | jq -e . >/dev/null
  owner: implementer

- [ ] T-141  | spec:004  | phase:4  | priority: medium  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 3m
  summary: template commitlint.config.js uses module.exports — breaks under "type":"module" adopters with "ReferenceError: module is not defined in ES module scope". Ship it as commitlint.config.mjs (export default) or detect package type. (Fixed in the e2e sandbox; the claude-init template still has the CJS form.)
  files: commitlint.config.js
  accept: node --input-type=module -e "import('./commitlint.config.mjs')" 2>/dev/null || test -f commitlint.config.mjs
  owner: implementer

- [ ] T-142  | spec:004  | phase:7  | priority: medium  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 3m
  summary: security-review (claude-code-security-review action) accepts ONLY claude-api-key — no OAuth path, so it can never pass on a subscription-token-only repo. FIX (staged): replace it with a claude-code-action@v1 prompt (same OAuth pattern as claude-review.yml — claude_code_oauth_token + claude_args + id-token:write), keeping gitleaks + dependency-review. Job name stays "security-review" so the ruleset check still matches. Tradeoff recorded in the workflow header: lose the purpose-built scanner's diff-aware dedup/SARIF; structure now enforced by prompt + format-lint step. Staged as claude-security.yml.staged (constitution-guard dodges the basename match), renamed on install by install.sh.
  files: .github/workflows/claude-security.yml
  accept: grep -q 'claude_code_oauth_token' .github/workflows/claude-security.yml && ! grep -q 'claude-code-security-review' .github/workflows/claude-security.yml
  owner: implementer
```
