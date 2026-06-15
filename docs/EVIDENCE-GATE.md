# The evidence gate

`evidence-gate.yml` is a required merge check. A PR cannot merge into `main` unless
it proves the change works — either by carrying a complete evidence bundle, or by
qualifying for one of the two committed escape hatches.

## The default path (app / feature PRs)

A PR that touches application source must carry proof:

1. PR body has a `## Evidence Bundle` section, every AC proven (no `UNPROVEN`),
   `Verdict … PASS`. Generate it with `bash .claude/scripts/collect-evidence.sh <spec-id>`
   and embed `pr-body.md`.
2. A `verify/<date>/evidence.json` rides **in this PR's diff** (G53) — stale or
   wrong-branch evidence is rejected. It must attest `ac_unproven=0`,
   `smoke_exit_max=0`, `verdict=PASS`, and a `commit` that is an ancestor of HEAD.
   If the PR touches a spec, the bundle's `spec` must match it.
3. The gate **re-executes** the proof on the checked-out head (G49): re-runs
   `verify.sh`, and if a Playwright rig exists for the spec, re-runs the journey +
   `spec-match.sh`. Divergence from the committed claims fails the gate.

## Escape hatches (committed `verify/<date>/no-ac.json`)

Some PRs have no spec-backed, browser-testable acceptance criterion, so the AC-proof
path above cannot apply. For those, commit a `verify/<date>/no-ac.json` declaring why.
The gate honors it **only** when the PR's file set matches the declared scope.

### `kind: "docs-only"` (default)

The PR touches **only** documentation-class paths: `docs/ specs/ plans/ tasks/
verify/ README CHANGELOG *.md`. Any non-docs path → rejected.

```json
{ "kind": "docs-only" }
```

### `kind: "harness-maintenance"`

The PR touches **only** harness-internal paths — `.claude/`, `.github/` — plus docs
and `verify/`. Never application source. This exists because a scripts/hooks/workflow
bugfix has no feature AC; without this scope every such PR had to be admin-bypassed
(cf. PR #13, #14).

```json
{
  "kind": "harness-maintenance",
  "reason": "why this is harness-internal and has no AC",
  "maintains": [".github/workflows/evidence-gate.yml"]
}
```

The gate computes app-source as a **deny-list**, not an allow-list: any changed file
**not** in `docs/ specs/ plans/ tasks/ verify/ .claude/ .github/ .mcp.json .gitignore
.gitleaks.toml *.md README CHANGELOG` is app source. A PR mixing `src/` (or any new
top-level app dir) with harness files is **never** eligible — those still need full
evidence. This makes the hatch fail-closed: a new application directory can't silently
slip through.

## Constitution-class workflow edits

`.github/workflows/evidence-gate.yml` is constitution-class (agent-write-blocked).
The agent stages the corrected file under `verify/<date>/.../staged/` and an operator
applies it with `cp` (which bypasses the Write/Edit hook):

```bash
APPLY=1 bash verify/2026-06-15-evidence-gate-maint/install.sh
```

Amendments to the constitution itself still go through `/constitution` with human
approval.
