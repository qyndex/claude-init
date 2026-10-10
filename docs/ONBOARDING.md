# Onboarding — 30 minutes to first ship

Adopt this harness in a new or existing repo. **Realistic time: 30-45 min on a fresh laptop** (accounting for OAuth flows, CI first runs, branch-protection setup). The "first ship" comes after the GitHub side is wired — about 30 min in.

> First time? Try `/onboard` from inside Claude Code — interactive 10-minute tour.

## Prerequisites (~5 min if all installed)

Hard requirements:
- **Claude Code CLI** ≥ 2.1.144 — https://code.claude.com (or `npm i -g @anthropic-ai/claude-code`)
- **Anthropic plan** — Build plan or higher (needed for Cloud Routines later; Pro is fine to start)
- **Git** ≥ 2.30
- **gh** (GitHub CLI) ≥ 2.40 — for PR automation, ship, ruleset import
- **jq** — for hook JSON parsing
- A package manager for your stack (pnpm / uv / cargo / go)

Recommended:
- `gitleaks` (`brew install gitleaks`) — secret scanning
- `prettier` / `ruff` / `rustfmt` / `gofmt` — auto-format hook
- `shellcheck` — harness-validate workflow
- `semgrep` (`brew install semgrep`) — in-agent SAST
- `c8` (Node) or `coverage` (Python) — coverage gate

## Step 1 — Install from reviewed source

Start at the root of a Git repository with reviewed changes committed/stashed. Use a clean
factory checkout at the approved source revision:

```bash
CLAUDE_INIT_REPO=/tmp/claude-init CLAUDE_INIT_REF="$(git -C /tmp/claude-init rev-parse HEAD)" bash /tmp/claude-init/scripts/install.sh
```

The installer resolves the exact commit and checks ownership before mutation. Existing
customized/foreign collisions block; preserve them and review an explicit reconciliation.
Do not overlay a Git archive or execute target-owned setup. Inspect the diff and commit only
reviewed process files. Existing ledgers/memory stay adopter-owned; new ones start empty.

## Step 2 — Configure that repository

See [FACTORY-ADOPTION.md](FACTORY-ADOPTION.md) for private recovery journals, guarded upgrades,
unsupported configuration and separate activation. Installation checks local tools but does
not install plugins, apply GitHub protection, copy pilot workflows, dispatch runs or enable
factory/production authority. Configure approved specs/tasks, stack capabilities and trusted
proof identities explicitly. Any optional plugin/cloud service requires its own configuration.

## Step 3 — Tighten the constitution (3 min)

Prefer adopter-owned AGENTS.md and local settings for conventions. Changes to manifest-owned
process files intentionally block upgrades until reviewed. Review `.claude/CLAUDE.md` for:

- **Tech stack** (Section 10 defaults table) — match your project
- **Quality bar** (Section 8) — adjust thresholds to your team
- **Decision-making defaults** — language, package manager, test framework

Commit:

```bash
git add .claude/CLAUDE.md
git commit -m "docs: tailor constitution to <project>"
```

## Step 4 — Customize MCP servers (2 min)

Open `.mcp.json`. By default, the active list is:

- `filesystem`, `git`, `github` — almost always useful
- `chrome-devtools`, `playwright` — for any web project
- `context7` — for library docs
- `postgres` — if you use Postgres
- `sentry` — if you use Sentry

Comment out anything you don't need (move it into `_disabled_examples`). Uncomment what you do need.

Set required env vars in your shell profile or in `.claude/settings.local.json`:

```json
{
  "env": {
    "GITHUB_PAT": "ghp_...",
    "DATABASE_URL": "postgresql://...",
    "ANTHROPIC_API_KEY": "sk-..."
  }
}
```

## Step 5 — Wire up GitHub (3 min)

In your GitHub repo settings:

1. **Secrets** (Settings → Secrets → Actions):
   - `ANTHROPIC_API_KEY` — required for the Claude Code Action workflows.
   - `GITLEAKS_LICENSE` — optional, for org-paid gitleaks.

2. **Branch protection** (Settings → Rules → Rulesets → New ruleset):

   Either click through the GitHub UI or import the ruleset:

   ```bash
   gh api repos/:owner/:repo/rulesets --method POST --input .github/rulesets/main-protection.json
   ```

   Required checks (add as your CI matures):
   - `lint-test` (from `.github/workflows/ci.yml`)
   - `review` (from `.github/workflows/claude-review.yml`)
   - `security-review` (from `.github/workflows/claude-security.yml`)
   - `harness-validate` (from `.github/workflows/harness-validate.yml`)

3. **Auto-merge** (Settings → General → Pull Requests):
   - ✅ Allow auto-merge
   - ✅ Automatically delete head branches

4. **Code owners** — edit `.github/CODEOWNERS` with your team handles.

## Step 6 — First Claude Code session (3 min)

```bash
claude
```

You'll see the session-start hook output:

```
[harness boot] Repo: my-project | Branch: main | Last commit: 8a92b3 feat: adopt claude code golden harness | Uncommitted files: 0 | Pending tasks: 0
```

Try the constitution flow if this is a brand-new project:

```
> /constitution
```

The agent will walk you through 3-4 questions and produce a tightened `CLAUDE.md`.

Then try the spec flow:

```
> /specify "add a /healthz endpoint that returns {ok: true, version: <git sha>}"
```

The architect agent will produce `specs/active/001-healthz.md` and ask you any open questions.

```
> /clarify
```

Resolves open questions.

```
> /plan
```

Architect produces `plans/active/001-healthz.md`.

```
> /tasks
```

Planner appends tasks to `tasks/TASKS.md`.

```
> /analyze
```

Cross-artifact consistency check.

```
> /implement all
```

Implementer agent walks the DAG with strict TDD.

```
> /verify
```

Verifier agent boots the app, hits `/healthz`, captures evidence.

```
> /review
```

Reviewer and security agents check the diff.

```
> /ship
```

Release agent pushes branch, opens PR, waits for CI, merges, deploys.

🎉 You shipped a feature end-to-end with the agent team.

## Step 7 — Learn the discipline (1 min)

Skim these files in order — they're short, they're load-bearing:

1. [.claude/CLAUDE.md](../.claude/CLAUDE.md) — the rules
2. [.claude/skills/specify/SKILL.md](../.claude/skills/specify/SKILL.md) — the methodology
3. [.claude/skills/tdd-loop/SKILL.md](../.claude/skills/tdd-loop/SKILL.md) — how to write code
4. [.claude/skills/verify/SKILL.md](../.claude/skills/verify/SKILL.md) — when "done" means done
5. [.claude/skills/context-budget/SKILL.md](../.claude/skills/context-budget/SKILL.md) — context economy
6. [.claude/memory/playbooks/new-feature.md](../.claude/memory/playbooks/new-feature.md) — the canonical recipe

## Troubleshooting

### Hooks not running

- `bash .claude/scripts/validate.sh` — checks executable bits
- `chmod +x .claude/hooks/*.sh .claude/scripts/*.sh .claude/statuslines/*.sh`

### MCP server fails to start

- Check `.mcp.json` env vars (e.g. `GITHUB_PAT` is set)
- Try `claude mcp list` to see what's configured
- Try `claude mcp reset-project-choices` if you've changed servers

### Branch protection blocks `/ship`

- Confirm CI workflows have run at least once on `main`
- Confirm secrets are set in repo settings
- Confirm required checks in the ruleset match the workflow job names exactly

### `claude --dangerously-skip-permissions` warning

- Don't use this flag with the harness — it bypasses the `pre-bash-guard` and `pre-write-secret-scan` hooks.
- If you must (e.g. CI container), REMOVE the `"disableBypassPermissionsMode": "disable"` line from `.claude/settings.json` for that container only (the project-locked string is what blocks bypass — boolean `true`/`false` forms are silently ignored by Claude Code, so setting `false` changes nothing) and ensure your CI sandbox is well-isolated.

## What to read next

- [docs/ARCHITECTURE.md](ARCHITECTURE.md) — how the pieces fit
- [docs/PLAYBOOK.md](PLAYBOOK.md) — operational recipes
- [docs/RESEARCH.md](RESEARCH.md) — every design decision + references
