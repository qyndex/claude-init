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
  summary: security-review (claude-code-security-review action) accepts ONLY claude-api-key — no OAuth path. FIX (staged): KEEP the purpose-built scanner (an OAuth claude-code-action prompt would forfeit diff-scoping, the separate false-positive pass, and SARIF — the real value of a gating security scan). Instead degrade gracefully: gate the LLM-scan step on `secrets.ANTHROPIC_API_KEY != ''` (skip + ::warning:: when absent), keep gitleaks + dependency-review UNCONDITIONAL so the job still enforces secret-scanning + dependency CVEs and can pass on a token-only repo. To make the LLM scan a hard gate: set ANTHROPIC_API_KEY and add security-review back to the ruleset required checks. (Considered + rejected the OAuth prompt swap, commit 6182b1f reverted in 1203dd6, on the user's call to preserve scanner rigor.)
  files: .github/workflows/claude-security.yml
  accept: grep -q 'claude-code-security-review' .github/workflows/claude-security.yml && grep -q "secrets.ANTHROPIC_API_KEY != ''" .github/workflows/claude-security.yml
  owner: implementer

- [ ] T-143  | spec:004  | phase:7  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 5m
  summary: FINDING-17 (live-e2e 2026-06-13) — the security-review job uses gitleaks/gitleaks-action@v2, which requires a PAID GITLEAKS_LICENSE secret on ANY repo owned by a GitHub ORGANIZATION. It hard-exits "[org] is an organization. License key is required." and fails the whole job with nothing actually leaked — so security-review can never pass on an org repo out of the box. (The Anthropic scanner itself ran clean, findings_count=0; gitleaks was the sole failure.) FIX (staged): replace the marketplace action with the gitleaks CLI (download pinned v8.30.1 tarball, run `gitleaks git --redact --exit-code 1`) — same MIT-licensed scanner, no licence key for any account type, same blocking behavior. Staged in claude-security.yml.staged.
  files: .github/workflows/claude-security.yml
  accept: grep -q 'gitleaks git' .github/workflows/claude-security.yml && ! grep -q 'gitleaks/gitleaks-action' .github/workflows/claude-security.yml
  owner: implementer
```
