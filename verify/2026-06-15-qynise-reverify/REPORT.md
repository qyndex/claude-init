# qynise brownfield re-verification vs latest factory — 2026-06-15

**Goal:** re-run the brownfield adoption test against the *current* factory
(`51e16b7`, incl. today's `.shellcheckrc` evidence-gate fix, validator
multi-token-id fix, reconcile `--upgrade`) to confirm no regression vs the
prior passing run (PR #14 / `4438aea`).

**Method (unchanged from prior run):** disposable detached worktree at qynise's
pre-harness commit `d58ed17d`; factory exported via `git archive 51e16b7`; full
greenfield-into-brownfield flow (factory tree → `setup.sh`); sha256 baseline of
all 4328 non-harness app files before/after. Real repo
`/Volumes/M/sourcecode/qyndex/qynise` never written — all work in `/tmp/qynise-reverify/`.

## Verdict: PASS with one NEW finding (F5)

### Regression checks — all green
- **F1 (spec-pruning leak) HOLDS:** `setup.sh` archived factory specs 001-003 →
  `docs/factory-history/specs/`, factory tasks → `TASKS.factory.md`; **zero
  dangling T-129/130/131 refs** in `tasks/TASKS.md`. Artifacts gate clean.
- **Security-critical (harness-doctor) all green:** `disableBypassPermissionsMode=disable`,
  hooks executable, constitution ≤300 lines, no `@latest` MCP pins.
- **validate.sh: 12 failures — all qynise's OWN backlog** (11 custom commands
  missing `disable-model-invocation`, 1 `demo-gate.yml` OAuth). Identical set to
  the prior run; NOT harness bugs.
- **harness-doctor ✗ items = post-adoption operator-wiring TODOs** (install
  routines, set `CLAUDE_CODE_OAUTH_TOKEN`, apply server-side ruleset, sync
  STATE.md) — expected state of a fresh adoption, matches prior run.

### App-code integrity
- **4327/4328 files byte-for-byte identical.** Sole delta: **README.md** —
  not missing, but **clobbered** (594 lines → factory's 218-line harness README;
  original content destroyed, not appended). → see F5.

## F5 (NEW, REAL) — documented brownfield step clobbers the project's root files

CLAUDE.md line 145 instructs brownfield adopters to run, into the target repo root:

```
git -C /tmp/claude-init archive HEAD | tar -x -C .
```

The factory ships its own **README.md, CLAUDE.md, .gitignore, .mcp.json** at repo
root. `tar -x -C .` extracts these *over* the project's existing files with **no
backup** — silently destroying the project's README and root developer guide.

- The line's only warning is about gitignored-state leakage (`cp -r` vs
  `git archive`); it does **not** warn that factory root files clobber the project's.
- `reconcile-claude-dir.sh` is **selective** (only `.claude/`, `.github/`, named
  root configs, named docs) and does NOT touch README — so the *reconcile* step is
  safe. The hazard is entirely in the **pre-reconcile `tar -x` step** the docs
  mandate.
- Severity: HIGH for a brownfield repo with a real README/CLAUDE.md. The prior
  test missed it because it focused on `.claude/`-internal merge correctness, not
  root-file collisions.

**Suggested fix:** mirror the upgrade path — extract to `/tmp/factory` first, then
let `reconcile-claude-dir.sh` selectively copy. I.e. change CLAUDE.md line 145 to
`tar -x -C /tmp/factory` + `reconcile … --from /tmp/factory`, and have reconcile
back up + no-clobber README.md/CLAUDE.md (or skip them entirely, drafting AGENTS.md
as it already does).

## Workspace (disposable)
- `/tmp/qynise-reverify/wt` — detached worktree @ d58ed17d (remove: `git -C /Volumes/M/sourcecode/qyndex/qynise worktree remove --force /tmp/qynise-reverify/wt`)
- `/tmp/qynise-reverify/factory` — factory export @ 51e16b7
- baseline/after sha + appdiff under `/tmp/qynise-reverify/`
