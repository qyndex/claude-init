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
  files: .github/workflows/claude-security.yml, .gitleaks.toml
  accept: grep -q 'gitleaks git' .github/workflows/claude-security.yml && ! grep -q 'gitleaks/gitleaks-action' .github/workflows/claude-security.yml && test -f .gitleaks.toml
  owner: implementer
  note: Also ships .gitleaks.toml — the CLI's generic-api-key entropy rule false-positived on harness DOC prose (skill SKILL.md `description:` frontmatter, security tables): 2 leaks found in .claude/skills/{flask-realtime,security-guard}/SKILL.md. Config extends the default ruleset (useDefault=true) and allowlists ONLY doc PATHS (.claude/{skills,agents,commands,rules,memory}/**.md, docs/**.md) — no content/stopword allowlist that could mask a real secret. Verified live against the sandbox: history scan 26 commits → no leaks (rc=0); real-secret detection intact (a non-example key is still caught; gitleaks' own AKIA…EXAMPLE keys are allowlisted by the DEFAULT ruleset, not by us).

- [ ] T-144  | spec:004  | phase:7  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 3m
  summary: FINDING-18 (live-e2e 2026-06-13) — the security-review job's actions/dependency-review-action@v4 step requires the GitHub Dependency Graph (and, on private repos, GitHub Advanced Security) to be enabled. On a private repo without GHAS it hard-exits "Dependency review is not supported on this repository" and fails the WHOLE security gate — even though gitleaks + the Anthropic scan passed. Same capability-gate class as T-143. FIX (staged): add `continue-on-error: true` to the dependency-review step so it is ADVISORY where the capability is absent (still runs/posts where supported), keeping gitleaks (secrets) + claude-code-security-review (code) as the hard gates. To make dependency-review blocking: enable Dependency Graph + GHAS on the repo, then drop continue-on-error.
  files: .github/workflows/claude-security.yml
  accept: awk '/Dependency review/{f=1} f&&/continue-on-error: true/{print; found=1} END{exit !found}' .github/workflows/claude-security.yml
  owner: implementer

- [ ] T-145  | spec:004  | phase:6  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 5m
  summary: FINDING-19 (live-e2e 2026-06-13, surfaced by the T-140 diagnostic) — validate.sh [swarm] hard-required .swarms/coordinator/fleet.json + decisions.log, but fleet.json is GITIGNORED mutable runtime state. A fresh CI checkout therefore lacks it, so the [swarm] category — and harness-validate — failed on EVERY clean checkout, including claude-init's own (it only passed locally because the dev had the runtime file present). This was the real CI-only cause behind harness-validate, masked until T-140 made the step print failing categories. FIX (done, validate.sh is script not constitution-class): [swarm] now SEEDS fleet.json + decisions.log to their documented empty shape if absent, then checks — self-heals deterministically without versioning runtime state. Verified: simulated fresh checkout (files removed) → seeded → 0 swarm failures, valid JSON.
  files: .claude/scripts/validate.sh
  accept: rm -f .swarms/coordinator/fleet.json && bash .claude/scripts/validate.sh --json | jq -e '.categories[]|select(.name=="swarm")|.failures|length==0' >/dev/null && jq -e . .swarms/coordinator/fleet.json >/dev/null
  owner: implementer

- [ ] T-146  | spec:004  | phase:6  | priority: medium  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 3m
  summary: FINDING-20 (live-e2e 2026-06-13) — validate.sh's [frontmatter] YAML check is SKIPPED when python3 lacks the yaml module (has_yaml=0 → no parse), but RUNS in CI where pyyaml is present. So a malformed frontmatter (e.g. an unquoted colon: `description: ADR-0001: foo` → "mapping values are not allowed") passes locally and fails only in CI — a silent local/CI divergence. The sandbox's .claude/memory/decisions/0001-*.md hit exactly this. Consider: (a) a regex fallback that catches the common unquoted-colon-in-value case even without pyyaml, and/or (b) WARN (not silently skip) when pyyaml is absent so the dev knows frontmatter wasn't validated. (The sandbox ADR itself was fixed by quoting the description.)
  files: .claude/scripts/validate.sh
  accept: grep -qiE 'pyyaml|yaml.*not.*(available|installed)|frontmatter.*skip' .claude/scripts/validate.sh
  owner: implementer

- [ ] T-147  | spec:004  | phase:7  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 5m
  summary: FINDING-21 (live-e2e 2026-06-13) — collect-evidence.sh emitted an EMPTY (0-byte) evidence.json whenever a spec had NO unproven ACs (the all-pass case). Line 138 built the unproven array via `printf ... | grep . | jq -R . | jq -sc . || echo []` — on empty input the inner jq printed `[]` AND grep exited 1 so the `|| echo []` ALSO fired, yielding `[]\n[]`, which is invalid JSON for the `--argjson ac_unproven` below; jq -nc then errored and wrote nothing. So a PERFECT (5/5 proven) run produced a broken bundle that fails evidence-gate. FIX (done): build the array directly — `[ ${#ac_unproven[@]} -eq 0 ] && []` else `printf | jq -Rsc 'split|map(select(length>0))'`; no grep/fallback race. Verified: 5/5-proven run now emits valid evidence.json (verdict PASS, unproven 0).
  files: .claude/scripts/collect-evidence.sh
  accept: bash .claude/scripts/collect-evidence.sh 001 >/dev/null 2>&1; jq -e . "$(ls -dt verify/*-001-* | head -1)/evidence.json" >/dev/null
  owner: implementer

- [ ] T-148  | spec:004  | phase:7  | priority: high  | created: 2026-06-13  | last_touched: 2026-06-13  | deps:  | parallel: yes  | est: 5m
  summary: FINDING-22 (live-e2e 2026-06-13) — .github/actions/setup-stack/action.yml hardcoded `node-version: "20"`. The evidence-gate re-runs the project's tests through setup-stack, so an app needing a newer Node (here `node:sqlite`, stable in 22+/24) failed the gate's smoke re-execution with "No such built-in module: node:sqlite" — which the gate mis-reported as G49 evidence divergence (the app + its 15 unit tests pass locally on Node 24). FIX (done; .github/actions/ is NOT constitution-class): resolve the project's declared Node version (.nvmrc / .node-version / package.json engines.node) like ci.yml does, falling back to a "22" floor only when the project declares none. (Sandbox side: added engines.node>=24 + .nvmrc 24.)
  files: .github/actions/setup-stack/action.yml
  accept: ! grep -qE 'node-version:\s*"20"' .github/actions/setup-stack/action.yml && grep -q 'node-version-file' .github/actions/setup-stack/action.yml
  owner: implementer
```
