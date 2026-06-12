# Spec 004 implementation report — CI gates fail against own code

Run: 2026-06-13 · Source: live greenfield E2E (docs/GREENFIELD-E2E-TEST-PLAN.md)

All five findings fixed. Writable fixes are in the main commit; constitution-class
fixes (hooks, workflows) are staged for operator apply via
`verify/2026-06-13-spec004-tasks/staged/install.sh`.

| AC | Task | Fix | Where | Verified |
|----|------|-----|-------|----------|
| AC-5 | T-136 | `audit-doc-claims.sh`: resolve gate tokens by basename (full-path claims) + skip `docs/factory-history/**` (vendored snapshot quoting hook output). Root bug was a lone apostrophe in a comment inside `<( )` breaking the parse. | `.claude/scripts/audit-doc-claims.sh` (writable) | `audit-doc-claims: all 31 gate claims resolve` rc=0 |
| AC-2 | T-133 | `lint-silent-failures.sh`: baseline ratchet — lock the 223 pre-existing unjustified swallows, fail only on NEW ones. Baseline can only shrink. | `.claude/scripts/lint-silent-failures.sh` + `.claude/state/silent-failure-baseline.json` (writable) | gate rc=0 within baseline; injected `\|\| true` → rc=1 with offending line; removed → rc=0 |
| AC-1 | T-132 | `.shellcheckrc` disables cosmetic codes (SC2012/2011/1091/2016/2221/2222) with rationale; substantive codes FIXED in hooks: SC2295 prefix-strip quoting in the two edit-guards + dep-freshness, SC1083 `'@{u}..HEAD'` quoting, SC2034 wired the dead `atlas_sha`/`current_sha` into the atlas staleness check. | `.shellcheckrc` (writable) + 5 staged hooks | simulated install tree: `shellcheck .claude/hooks/*.sh` clean; full-repo `-S warning` clean |
| AC-4 | T-135 | `commitlint.config.js` extends conventional, disables `subject-case` + `body-max-line-length` per §VI. Workflow drops `--extends` so the config is discovered. | `commitlint.config.js` (writable) + staged `commitlint.yml` | `feat(e2e): AC-5 …` accepted rc=0; bad type still 3 errors |
| AC-3 | T-134 | `merge-gate.yml`: (a) **live failure** — `gh run list --json …htmlUrl` → `url` (htmlUrl is not a field, `set -e` aborted before the scan); (b) age window uses repo `createdAt` from the API, not first-COMMIT date (git-archive adoption back-dates it). | staged `merge-gate.yml` | actionlint clean |

## Operator steps to finish

1. `APPLY=1 TARGETS=/Volumes/M/sourcecode/qyndex/harness-e2e-sandbox bash verify/2026-06-13-spec004-tasks/staged/install.sh`
2. Paste `verify/2026-06-13-spec004-tasks/staged/TASKS-append.md` into `tasks/TASKS.md`.
3. `bash .claude/scripts/validate.sh && shellcheck --format=gcc .claude/hooks/*.sh`

## Note on the credential-gated checks

`claude-review`, `security-review`, `anti-slop-triage` need the repo secret (now
set: `CLAUDE_CODE_OAUTH_TOKEN`). `security-review` accepts API keys only — it stays
red on a token-only repo (out of scope, FINDING-7/8 / oauth-fallback).
