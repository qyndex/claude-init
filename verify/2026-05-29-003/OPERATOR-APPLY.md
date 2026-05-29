# Spec 003 — Operator-apply bundle

These edits touch **constitution-class files** (`settings.json`, `.mcp.json`,
`.github/workflows/*`, `.claude/CLAUDE.md`). The Auto-Mode classifier correctly
blocks an agent from self-modifying its own permission/security config, so they
must be applied by the operator.

## How to apply

```bash
# 1. Clear the leaked guard var, then re-enable it deliberately for this session only:
unset FORCE_CONSTITUTION_EDIT
export FORCE_CONSTITUTION_EDIT=1     # the guard now LOGS each bypass to .claude/hooks/.log/

# 2. Apply each edit below (by hand, or paste into Claude with the var set).
# 3. Verify:
bash .claude/scripts/validate.sh
bash .claude/scripts/check-model-consistency.sh   # must be clean after T-123
# 4. CRITICAL: unset again so the guard is live for normal work:
unset FORCE_CONSTITUTION_EDIT
```

---

## T-116 + T-117 + T-118 — settings.json permissions (AC-5, AC-6, AC-7)

**T-116/117: replace bare `"Edit"` (line 46) with scoped Edit + add Write targets.**
Replace:

```json
      "Edit",
      "Write(src/**)",
```

with:

```json
      "Edit(src/**)",
      "Edit(tests/**)",
      "Edit(specs/**)",
      "Edit(plans/**)",
      "Edit(tasks/**)",
      "Edit(docs/**)",
      "Edit(verify/**)",
      "Edit(.swarms/**)",
      "Edit(initiatives/**)",
      "Edit(.claude/memory/**)",
      "Edit(.claude/memory.proposed/**)",
      "Edit(.claude/state/**)",
      "Edit(.claude/rules/**)",
      "Edit(OVERNIGHT_REPORT.md)",
      "Edit(ADOPTION-REPORT.md)",
      "Edit(roadmap.md)",
      "Edit(OKRs.md)",
      "Write(initiatives/**)",
      "Write(.claude/rules/**)",
      "Write(OVERNIGHT_REPORT.md)",
      "Write(ADOPTION-REPORT.md)",
      "Write(roadmap.md)",
      "Write(OKRs.md)",
      "Write(src/**)",
```

**T-117: add `./initiatives` to `additionalDirectories`** (after `"./.swarms"`):

```json
      "./.swarms",
      "./initiatives"
```

**T-118: close credential deny-list gaps.** In the `deny` array, add to BOTH the
Read and Write groups:

```json
      "Read(**/*.p12)", "Read(**/*.pfx)", "Read(**/.npmrc)", "Read(**/.netrc)",
      "Read(**/_netrc)", "Read(**/.git-credentials)", "Read(**/*.kdbx)",
      "Read(**/.pypirc)", "Read(**/*.kubeconfig)", "Read(**/kubeconfig)",
      "Read(**/.docker/config.json)", "Read(**/*.tfstate)", "Read(**/.aws/credentials)",
      "Write(**/*.p12)", "Write(**/*.pfx)", "Write(**/.npmrc)", "Write(**/.netrc)",
      "Write(**/_netrc)", "Write(**/.git-credentials)", "Write(**/*.kdbx)",
      "Write(**/.pypirc)", "Write(**/*.kubeconfig)", "Write(**/kubeconfig)",
      "Write(**/.docker/config.json)"
```

Then extend `validate.sh` security-invariant check to assert these patterns are
present (so a future edit can't silently drop them).

---

## T-120 — remove inert sandbox block + wire real runtime sandbox (AC-8)

**Delete** the entire `"sandbox": { ... }` block from `settings.json` (lines ~330-355).
It is not a recognized settings-schema key — Claude Code silently ignores it, so it
provides ZERO containment despite the comment claiming it does.

**Wire the real mechanism** in `.claude/routines/overnight-build.yml` — the
autonomous run must launch with the OS-level sandbox / `--sandbox` flag (the
supported runtime mechanism), not rely on settings.json. Document the chosen flag
in `docs/AUTOPILOT.md` (near the existing run-config block).

**Correct the docs** — in `.claude/CLAUDE.md §X` and `§XI`, change wording that
implies settings.json enforces the sandbox to point at the runtime flag instead.

---

## T-121 — scope filesystem MCP + pin alwaysLoad servers (AC-9, AC-10)

**`.mcp.json` line 90** — the filesystem server is rooted at `.` and reads through
its OWN access path, which the settings `deny: Read(**/*.pem)` does NOT constrain.
Either scope its root away from secrets, OR (minimum) document the bypass + mitigation
in `.claude/CLAUDE.md §X`. Recommended: keep root `.` but add a CLAUDE.md §X note:
"the filesystem MCP server's read path is NOT gated by the settings deny-list; never
store secrets in the repo tree; gitleaks PreToolUse + .gitignore are the mitigations."

**Pin the two alwaysLoad servers** (lines 90, 98):

```json
"args": ["-y", "@modelcontextprotocol/server-filesystem@2025.8.21", "."],   // pin to a real published version
"args": ["mcp-server-git==0.6.2", "--repository", "."],                     // pin to a real published version
```

(Verify the exact latest-stable versions on npm / PyPI before pinning.)

---

## T-123 — bump CI workflow model pins to claude-opus-4-8 (AC-11)

THREE files pin the stale `claude-opus-4-7` (the spec named two; `claude.yml` is the third):

```
.github/workflows/claude-review.yml:31     model: claude-opus-4-7   → claude-opus-4-8
.github/workflows/claude-security.yml:40   model: claude-opus-4-7   → claude-opus-4-8
.github/workflows/claude.yml:43            model: claude-opus-4-7   → claude-opus-4-8
```

After this, `bash .claude/scripts/check-model-consistency.sh` goes clean (it now
scans workflows for the stale literal — added in T-124).

---

## T-125 — fix worktree schema violations (AC-13)

`settings.json` lines 359-360:

- `"baseRef": "head"` → the schema enum does not include `"head"`. Set to a
  schema-valid value (`"none"` if no auto-base is wanted, or remove the key to take
  the default). Confirm against the Claude Code settings schema for v2.1.144+.
- `"symlinkDirectories": [...]` → flagged "not allowed" by the schema; either remove
  it or move it to the supported location. If removed, background worktrees won't
  symlink `node_modules`/`.venv` (slower bg runs) — decide deliberately.

---

## T-113 — server-side TDD-ledger re-check in harness-validate.yml (AC-3)

Add a step to the `harness-validate` job that re-runs the ledger check server-side
(where the agent can't set SKIP\_\*). Suggested step (uses a new helper
`.claude/scripts/check-tdd-ledger.sh`, which the agent CAN write — only the workflow
edit is gated):

```yaml
- name: TDD ledger gate (server-side, SKIP_* cannot apply)
  run: bash .claude/scripts/check-tdd-ledger.sh
```

Per R-1, `check-tdd-ledger.sh` checks only tasks whose `verify/` evidence is
git-tracked, and warns (not fails) on missing-but-untracked.

---

## T-114 — evidence-gate.yml: make evidence.json mandatory (AC-4)

In `.github/workflows/evidence-gate.yml`, the "Re-assert from committed evidence.json"
step (line ~44) currently falls through to trusting PR-body prose when no
`evidence.json` exists (line 56). Change the `else` branch from:

```bash
          else
            echo "No committed evidence.json — relying on PR-body assertion."
          fi
```

to:

```bash
          else
            echo "::error::No committed evidence.json — PR-body prose is not sufficient. Run collect-evidence.sh."
            exit 1
          fi
```

Per R-3, allow a `verify/<date>/no-ac.json` sentinel for docs-only PRs so they
produce a real artifact rather than relying on prose.

````

---

## After applying all of the above

```bash
unset FORCE_CONSTITUTION_EDIT          # re-arm the guard
bash .claude/scripts/validate.sh       # expect: all checks passed
bash .claude/scripts/check-model-consistency.sh   # expect: clean
````

Then mark T-113, T-114, T-116, T-117, T-118, T-120, T-121, T-123, T-125 as `[x]`
in tasks/TASKS.md (with paired red/green ledger), close out T-115/T-119/T-122,
and I'll finish T-128 (REPORT.md + final validate).
