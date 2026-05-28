# Playbook — operational recipes

Cookbook of common workflows. Each entry assumes the harness is already adopted.

## Build a feature end-to-end

See [.claude/memory/playbooks/new-feature.md](../.claude/memory/playbooks/new-feature.md).

## Fix a bug

Two paths depending on whether the cause is obvious.

### Cause is obvious (saw it, can describe it)

```
/specify "fix: <symptom>"            # spec the bug
/plan                                # one-phase plan with the fix
/tasks                               # 1-3 tasks: failing test, fix, regression test
/implement all
/verify
/review
/ship
```

### Cause is non-obvious

```
/debug "<symptom or error>"
```

The debugger agent runs the 4-phase loop (reproduce → isolate → diagnose → fix proposal). The proposal hands off to the implementer.

## Refactor

Refactors **need** a spec — they're high-risk because they touch many files without changing behavior.

```
/specify "refactor: <module> for <reason>"
   # The spec's acceptance criteria are "all existing tests still pass" + "no public API change"
/plan
   # Phase 1: characterization tests (capture current behavior)
   # Phase 2: refactor under green tests
   # Phase 3: deprecate / remove old code
/tasks
/implement all
/verify   # full regression + browser E2E
/review
/ship
```

## Adopt a new dependency

Don't `npm install` blindly. Research first.

```
/research "compare <lib-a> vs <lib-b> vs <lib-c> for <use case>"
   # Researcher agent produces docs/research/<date>-<topic>.md with citations
```

Then specify the integration:

```
/specify "integrate <lib> for <feature>"
/plan      # include the lib version, justification, alternative considered
/tasks
/implement all
```

## Investigate a production incident

```
/debug "<production symptom>"
   # captures evidence and produces a hypothesis
```

After resolution, write a postmortem:

```
cp .claude/memory/incidents/0000-template.md .claude/memory/incidents/<date>-<slug>.md
# fill in: timeline, root cause, action items, lessons
```

Append a one-liner to `.claude/memory/MEMORY.md`.

## Set up a project for unattended overnight work

Pre-flight:

```
git checkout -b auto/<topic>
git worktree add ../<project>-auto auto/<topic>
cd ../<project>-auto
```

In Claude Code:

```
/loop --budget 500000 --until 02:00
```

The loop walks `tasks/TASKS.md`, one task per iteration with fresh context. Stops on:

- Budget reached
- 2 consecutive iterations with no diff
- 2 consecutive verify failures
- Security check failure
- User interrupt

Resumable: `plans/active/<id>-progress.md` is written every iteration.

## Update a dependency safely

```
# Bot does this automatically via .github/workflows/auto-merge-dependabot.yml
# For manual updates:

/specify "chore(deps): update <pkg> to <version>"
/plan
/tasks       # 1 task: bump version, run tests
/implement all
/verify       # critical for major version bumps
/review --security    # always for dep updates
/ship
```

## Add a new MCP server

1. Find the official repo (check [modelcontextprotocol/servers](https://github.com/modelcontextprotocol/servers) or [registry.modelcontextprotocol.io](https://registry.modelcontextprotocol.io/))
2. Add to `.mcp.json` under `mcpServers`:
   ```json
   "myserver": {
     "type": "stdio",
     "command": "npx",
     "args": ["-y", "@vendor/mcp-server"]
   }
   ```
3. Pin the version (avoid `latest` in production)
4. Audit the source repo if it's community-maintained
5. Restart Claude Code (or run `/mcp` and approve)
6. Test with `claude mcp list`

## Open a draft PR for review without full /ship

```
git push -u origin <branch>
gh pr create --draft --title "feat: <title>" --body "WIP — looking for early feedback on <thing>"
```

Claude's PR review workflow will still run (it doesn't gate on draft status by default), giving you a first-pass review before you mark ready.

## Cancel a runaway loop

```
Ctrl-C in the Claude Code terminal
```

The loop respects `^C` and writes a final entry to `plans/active/<id>-progress.md`. To clean up the worktree:

```
cd <main-repo>
git worktree remove ../<project>-auto
git branch -D auto/<topic>     # if you want to discard
# OR
git checkout auto/<topic>
git merge --squash --no-commit  # to inspect what got done
```

## Add a new agent

1. Pick the tier: `core` (always-needed), `quality` (review/verify), or `specialist` (one-off domain expertise)
2. Create `.claude/agents/<tier>/<name>.md` with frontmatter (copy from an existing agent as template)
3. Write the system prompt — focus on mandate, hard rules, workflow, done means
4. Run `bash .claude/scripts/validate.sh` to confirm frontmatter is valid
5. Restart Claude Code to pick up new agents

## Add a new skill

1. Create `.claude/skills/<name>/SKILL.md` with frontmatter
2. The `description` is critical — it drives auto-triggering. Include "when to use" cues
3. Body is loaded only on invocation, so it can be longer
4. If the skill is invokable by `/<name>`, set `user-invocable: true` (default)
5. For path-scoped skills, set `paths: ["src/api/**/*"]`
6. Run `bash .claude/scripts/validate.sh`

## Add a new hook

1. Add the script to `.claude/hooks/<event>-<purpose>.sh`
2. Make it executable: `chmod +x .claude/hooks/*.sh`
3. Register in `.claude/settings.json` under `hooks.<EventName>`:
   ```json
   "PreToolUse": [{
     "matcher": "Bash",
     "hooks": [{ "type": "command", "command": "bash .claude/hooks/<your-hook>.sh" }]
   }]
   ```
4. For PreToolUse hooks that block: emit JSON to stdout:
   ```json
   {
     "hookSpecificOutput": {
       "hookEventName": "PreToolUse",
       "permissionDecision": "deny",
       "permissionDecisionReason": "..."
     }
   }
   ```
5. Test by running the hook manually with sample stdin

## Roll back a release

See [.claude/memory/playbooks/rollback.md](../.claude/memory/playbooks/rollback.md).

## Diagnose a flaky test

See [.claude/memory/playbooks/flaky-test.md](../.claude/memory/playbooks/flaky-test.md).

## When `/ship` is blocked

`/ship` refuses to proceed if any quality gate fails. Diagnose:

```bash
bash .claude/scripts/verify.sh   # local checks
gh pr checks <pr>                # CI checks
```

Common blockers:

- **Lint/typecheck failing** → run locally, fix, push
- **Security review flagged a high** → address with implementer, push
- **No verify report** → run `/verify`
- **Branch protection** → confirm secrets + ruleset configured

## Legitimately edit constitution-class files

`.claude/CLAUDE.md` (and other constitution-class files) are protected from agent
writes by **two independent layers** — so a normal Claude edit will be refused:

1. **Hook layer** — `.claude/hooks/pre-edit-constitution-guard.sh` denies the Edit
   (PreToolUse, exit 2) unless `FORCE_CONSTITUTION_EDIT=1` is set in the shell.
2. **Auto Mode classifier** — independently treats any write to the constitution as
   self-modification and hard-blocks it; this layer does **not** honor the env var.

The env-var escape hatch lifts only the hook, not the classifier. So to make a
deliberate, operator-owned change to the constitution, edit it **outside Claude**:

```bash
# Recommended: a one-shot human edit, then commit yourself.
$EDITOR .claude/CLAUDE.md
git add .claude/CLAUDE.md
git commit -m "docs(constitution): <what changed and why>"
```

```bash
# Scripted operator edit (still you, not the agent). The env var documents intent
# and satisfies the hook for any tooling that respects it.
FORCE_CONSTITUTION_EDIT=1 sed -i '' 's/old/new/' .claude/CLAUDE.md
```

Why this is intentional: the constitution is the agent's operating law. An agent that
can rewrite its own law can rationalize around every other guardrail. Editing it is a
human act, gated behind a deliberate out-of-band step — never something the autopilot
loop can reach. See `.claude/memory/incidents/2026-05-28-sec-constitution-unprotected.md`.

## Reset the harness state (start clean)

```bash
# Archive current work
git stash
mkdir -p archive/$(date +%Y%m%d)
mv specs/active/* plans/active/* archive/$(date +%Y%m%d)/ 2>/dev/null || true

# Truncate TASKS.md (keep header)
head -30 tasks/TASKS.md > /tmp/TASKS-header
mv /tmp/TASKS-header tasks/TASKS.md

# Clear hook logs
rm -rf .claude/hooks/.log/

# Re-validate
bash .claude/scripts/validate.sh
```

## Subscription switching (Console ↔ Pro ↔ Max)

Round 6 B. Before switching the Anthropic subscription/auth principal:

### Pre-switch

```bash
# 1. Snapshot user-state to repo (auto-runs at session-end; do it explicitly to be sure)
bash .claude/scripts/mirror-user-state.sh

# 2. List in-flight background sessions
claude agents --json

# 3. Either let them finish, or stop them — background workers re-authenticate
#    per-launch, so switching mid-flight will orphan them
claude agents stop <session-id>

# 4. List scheduled tasks (Anthropic Console UI or /tasks list inside claude)
#    Note: scheduled-task registration is auth-principal-scoped
```

### Switch

Switch your subscription as usual via [console.anthropic.com](https://console.anthropic.com) / claude.ai settings.

### Post-switch

```bash
# 1. Re-install scheduled tasks (registration didn't survive the auth change)
bash .claude/scripts/install-overnight-tasks.sh

# 2. Re-verify Cloud Routines (requires claude.ai login, NOT API key)
#    Visit https://claude.ai/code/routines and confirm your overnight-build is intact
#    If you're switching TO an API-key-only subscription, Cloud Routines won't run —
#    fall back to local-overnight-build.sh

# 3. MCP servers will re-prompt for auth on first use (this is expected; the
#    ~/.claude/mcp-needs-auth-cache.json is per-machine)

# 4. Verify project mirror is intact
ls .claude/.user-state-mirror/

# 5. Session transcripts under ~/.claude/projects/<slug>/ are filesystem-local,
#    so they survive the switch. Test:
claude --continue
```

### If your home dir was wiped during the switch

```bash
bash .claude/scripts/restore-user-state.sh
# Then continue
claude --continue
```

### If you moved the project to a different path

Project identifier is `pwd | sed 's|/|-|g'` (path slug, NOT git remote). Moving the
repo from `/Volumes/M/foo` → `/Users/me/foo` orphans `~/.claude/projects/-Volumes-M-foo/`.

```bash
# Tell restore which OLD slug to pull from
bash .claude/scripts/restore-user-state.sh "-Volumes-M-foo"
```

## Recover from a killed session

```bash
# Triage: what was in flight?
bash .claude/scripts/resume-or-restart.sh

# Continue the most recent session:
claude --continue

# Or resume a specific session:
claude --resume <session-id>

# Clean restart (discards WIP commits):
bash .claude/scripts/resume-or-restart.sh --clean && claude
```

The session-start-context hook surfaces a `⚠ KILLED-SESSION` banner whenever it detects a stale heartbeat — you don't have to remember to check.
