---
name: ship
description: Final phase — push branch, open PR, wait for CI, merge, deploy. Phase 8 of the eight-phase workflow. Delegates to release agent. Refuses to proceed if any quality gate fails.
when_to_use: All prior phases complete. User says "ship it", "open the PR", "merge", "deploy", "release".
argument-hint: "[--draft] [--no-merge] [--no-deploy]"
model: sonnet
allowed-tools: Read, Glob, Grep, Bash, TodoWrite
context: fork
agent: release
---

# Ship

Push, PR, CI, merge, deploy. With gates.

## Process

0. **Live-ruleset preflight (e2e-audit ci-gates-2)** — the ruleset FILE is inert until applied server-side; without a live ruleset every "required" check is advisory and merge-on-red is possible.
   ```bash
   live=$(gh api "repos/{owner}/{repo}/rulesets" 2>/dev/null || true)
   printf '%s' "$live" | jq -e '[.[] | select(.target=="branch" and .enforcement=="active")] | length > 0'
   ```
   If this fails (no active branch ruleset, or the API is unreadable): **REFUSE to merge**. Report to the operator with the apply command — `gh api repos/{owner}/{repo}/rulesets --method POST --input .github/rulesets/main-protection.json` — and stop after step 7 (PR open + CI watch are fine; merge is not). `bash .claude/scripts/harness-doctor.sh` shows the same finding as "live branch ruleset".
1. **Verify the quality bar** from `.claude/CLAUDE.md §8`. Every box must be checked.
2. **Collect evidence (Round 10 C)** — `bash .claude/scripts/collect-evidence.sh <spec-id>`. ABORT if it exits non-zero (an AC is unproven or smoke is red). This produces `verify/<date>-<feature>/pr-body.md`.
3. **Commit the lightweight evidence** — `git add verify/<date>-<feature>/{EVIDENCE.md,pr-body.md,evidence.json,results.json,screenshots,traces}` (heavy binaries are gitignored + ride as CI artifacts).
4. **Stage and commit** any final changes (CHANGELOG, version bump).
5. **Push the branch** (`git push -u origin <branch>`).
6. **Open the PR with the evidence bundle as the body**:
   `gh pr create --body-file verify/<date>-<feature>/pr-body.md`
7. **Wait for CI** (`gh pr checks --watch`) — `evidence-gate` is now a required check; it blocks merge if any AC is unproven.
8. **Ask the user** to confirm merge.
9. **Squash-merge** (`gh pr merge --auto --squash --delete-branch`).
10. **Tag the release** if semver bump (`gh release create`).
11. **Trigger deploy** (or watch auto-deploy).
12. **Update memory** with any non-obvious learnings.

## Hard rules

- **No bypass.** Required checks must be green.
- **No merge without a live ruleset.** "Required" checks only block when a server-side active branch ruleset exists — preflight step 0 is non-negotiable.
- **No `--force`.** Ever, on main/master.
- **User confirms merge.** Even if all checks pass.
- **User confirms deploy.** Production always requires explicit go.
- **ADR check (gap-audit G39/G40).** If the diff touches architectural surfaces (migrations, settings, auth, API contracts) and no `.claude/memory/decisions/` file is added/updated or cited in the plan's References, STOP and warn loudly — create the missing ADR via `adr-new.sh` before shipping. CI's adr-gate enforces the same rule.

## Quality bar (from CLAUDE.md §8)

- [ ] Spec approved
- [ ] Plan approved
- [ ] All tasks complete (each with red→green ledger — Round 10 A)
- [ ] Unit tests pass + assertion-density gate clean
- [ ] Integration tests pass
- [ ] E2E verified — every AC proven via spec-match (Round 10 B)
- [ ] **Evidence bundle generated** (`collect-evidence.sh` exit 0) and embedded in PR body
- [ ] Code review approved
- [ ] Security review clean
- [ ] Lint + typecheck clean
- [ ] Docs updated

## Output

```
PR opened: <url>
Checks: <green/red>
Merged: <yes/no>
Tagged: v<version>
Deployed: <yes/no/scheduled>
```

After ship: "<feature> shipped. PR <url>. Tag v<version>. Deploy <status>."
