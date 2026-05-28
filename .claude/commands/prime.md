---
description: Prime Claude with this project's structure and conventions in one read. Use at the start of a fresh session when CLAUDE.md isn't enough context (e.g., starting work on an unfamiliar module). Modeled on disler/infinite-agentic-loop prime pattern.
argument-hint: "[module path, optional]"
allowed-tools: Bash, Read, Glob, Grep
disable-model-invocation: true
---

# /prime — Load project context

Pull together the minimum context needed to start working confidently.

## Process

1. Read `.claude/CLAUDE.md` — the constitution.
2. Read `.claude/memory/MEMORY.md` — the index of decisions/patterns/incidents.
3. Read `README.md` if present.
4. If `$ARGUMENTS` is a path, read the top-level files there and `find` the directory shape.
5. Read the most recent active spec/plan (if any).
6. Run `git log -10 --oneline` for recent activity.

```!
echo "=== Repo shape ==="
find . -maxdepth 2 -type d -not -path '*/.git*' -not -path '*/node_modules*' -not -path '*/.venv*' -not -path '*/target*' 2>/dev/null | head -30
```

```!
echo
echo "=== Recent commits (10) ==="
git log -10 --oneline 2>/dev/null
```

```!
echo
echo "=== Languages / stacks detected ==="
[ -f package.json ] && echo "- node ($(node -v 2>/dev/null || echo 'unknown'))"
[ -f pyproject.toml ] && echo "- python"
[ -f Cargo.toml ] && echo "- rust"
[ -f go.mod ] && echo "- go"
[ -f Gemfile ] && echo "- ruby"
[ -f Dockerfile ] && echo "- docker"
[ -f docker-compose.yml ] && echo "- compose"
```

After loading, output a **short** orientation (5-8 bullets):
- Stack and package manager
- Top-level structure
- Active work (spec/plan/branch)
- Recent activity direction
- Any non-obvious convention from CLAUDE.md or MEMORY.md
- Suggested next command (`/status`, `/specify`, etc.)
