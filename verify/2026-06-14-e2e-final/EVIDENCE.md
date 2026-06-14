# Greenfield E2E — final verification (spec 004, T-140..T-157)

Date: 2026-06-14
Question answered: *"Is claude-init fully verified end-to-end via the greenfield
todo app (harness-e2e-sandbox), no gap? What about T-140..T-155?"*

## Honest verdict

**The harness mechanism is verified end-to-end against a real app, and every
T-140..T-157 accept passes against the to-be-shipped (staged) state.** One
delivery gap remains that is **operator-only by design** and cannot be closed by
the agent: 6 corrected `.github/workflows/*` files are committed in spirit
(staged + working tree) but not yet pushed to `claude-init` `main`, because
`.github/workflows/*` is constitution-class (agent-write-blocked) and push-to-main
is user-only.

## What was proven live

| Evidence | Result |
|---|---|
| Good feature PR (sandbox #2) | merged GREEN |
| Bad gauntlet PR (sandbox #3) | stays BLOCKED |
| osv-scanner CLI on real app | scanned **265 packages** live (sandbox) |
| daily-batch on sandbox `main` | `completed/success` 2026-06-14 |
| daily-batch on claude-init `main` | `completed/success` 2026-06-14 |
| security-review @ max-turns 40 | `COMPLETED/SUCCESS` (PR #11/#12) |

## T-140..T-157 accept sweep (against the staged set = what lands on main)

12/12 grep accepts PASS; script accepts (T-140 validate --json, T-145 swarm seed,
T-146 yaml-skip note, T-149 verify.sh pw-install) PASS against live scripts.
T-141 / T-147 require a node project / spec scaffold → exercised in the **sandbox**,
not the template (template has no app stack — by design, per root CLAUDE.md).

## The remaining gap (operator action)

`origin/main` of claude-init still carries the **old** versions of 6 workflows;
the **corrected** versions sit in `verify/2026-06-13-spec004-tasks/staged/*.staged`
(and in the working tree, uncommitted):

| File | Old on main | Corrected (staged) | Task |
|---|---|---|---|
| daily-batch.yml | `osv-scanner scan source -r --no-ignore ./` (walks `/`, false-green) | `scan source --recursive .` + "No package sources found" warning branch | T-154, T-151 |
| adr-gate.yml | `${{ github.base_ref }}` inline in `run:` | `BASE_REF` via `env:` (injection fix) + SC2254 justified | T-152 |
| quarterly-archive.yml | inputs.quarter inline + wrong step id | `QUARTER` via env, `id: archive`, correct outputs ref | T-152 |
| claude.yml | invalid `model:` / `trigger_phrases:` | `claude_args: --model …`, `trigger_phrase`, OAuth token | T-153 |
| claude-review.yml | no dependabot skip | `github.actor != 'dependabot[bot]'` | T-155 |
| pr-review.yml | no dependabot skip | same | T-155 |

Why claude-init main is *green today despite the bug*: the template harness has
**no app stack / no lockfile**, so the buggy `-r --no-ignore ./` osv walks `/`,
finds nothing, and the old code path silently passed. The corrected version emits
a loud "dependency CVE coverage is OFF — commit a lockfile" warning instead of a
false-green. Real CVE work is proven on the **sandbox** (265 packages).

actionlint: the two corrected files (adr-gate, quarterly-archive) are now CLEAN.
Pre-existing SC2044/SC2086/SC2038 style warnings in harness-validate/perf-budget
are **identical on origin/main** (not regressions) and no CI job gates on
actionlint — left untouched (surgical scope).

## Operator steps to close the last gap

```bash
cd /Volumes/M/sourcecode/qyndex/claude-init
APPLY=1 bash verify/2026-06-13-spec004-tasks/staged/install.sh   # cp staged → .github/workflows (sanctioned operator path)
# paste verify/2026-06-13-spec004-tasks/staged/TASKS-append-3.md into tasks/TASKS.md  (constitution-class)
git add -A && git commit   # conventional-commit per §VI
git push / open PR / squash-merge to main
```

After that push, `git show origin/main:.github/workflows/daily-batch.yml | grep -q
'No package sources found'` passes, and the T-154 accept is green against main —
closing the only outstanding item.
