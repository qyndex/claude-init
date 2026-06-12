---
name: instinct
description: Continuous-learning observer. PostToolUse + Stop hooks write JSONL observations; a background Haiku subagent extracts atomic "instincts" (trigger → action, confidence-rated, domain-tagged). Project-level by default; promotes to global at 2+ projects. From affaan-m/ECC continuous-learning-v2.
when_to_use: "Auto-runs via hooks. Manual invocation by user: \"extract instincts\", \"what did you learn\", \"review instincts\"."
model: inherit
---

# Instinct — Continuous Learning Observer

Most learning is one-shot ("don't do X again") and lost when the session ends. Instincts persist atomic lessons across sessions.

## What an instinct is

A single (trigger → action) pair with provenance:

```yaml
- id: i-<sha8>
  trigger: "user mentions 'prod migration'"
  action: "ask about peak hours and rebuild lock duration before suggesting"
  confidence: 0.7
  domain: db | frontend | auth | ci | security | refactor | general
  evidence:
    - session: <session-id> at <iso-ts>
    - commit: <sha>  (or PR: <url>, or incident: incidents/<file>)
  status: project | global
  created: <iso-date>
  reinforced: <count>
  last_seen: <iso-date>
```

## How it's captured

**PostToolUse hook** (`.claude/hooks/instinct-observer.sh`) appends to `.claude/memory/.cache/instincts/observations.jsonl` (gap-audit G25: path now matches the observer):

```jsonl
{"ts":"2026-05-27T22:31:00Z","tool":"Bash","cmd":"npm test","exit":1,"err":"timeout"}
{"ts":"2026-05-27T22:31:45Z","tool":"Edit","file":"src/auth.ts","diff_hint":"add 5s timeout"}
{"ts":"2026-05-27T22:32:10Z","tool":"Bash","cmd":"npm test","exit":0}
```

**Stop hook** (`auto-dream-check.sh`) calls `.claude/scripts/instinct-extract.sh` on every fire; the script self-gates on ≥50 new observations (`INSTINCT_EXTRACT_MIN`) — roughly every few sessions. Force manually via `/instinct extract`. The extraction pass:

1. Spawn fresh Haiku subagent (`claude -p` with empty context).
2. Subagent reads observations.jsonl since last extraction.
3. Subagent identifies repeated patterns: same kind of failure, same fix.
4. Subagent emits 0-5 candidate instincts.
5. Each candidate gets a confidence score (0.3-0.9).
6. Stored at `.claude/memory/instincts/active.yml`.

## How it's used

- **SessionStart**: `session-start-context.sh` greps active.yml for instincts whose `trigger` matches the current branch / task / open file. Injects top 3 matching as additional context.
- **UserPromptSubmit**: `skill-router.sh` checks if user prompt matches any instinct trigger. If yes, injects the action as a system-reminder.

## Promotion: project → global

Mechanics (gap-audit G26): `bash .claude/scripts/instinct-promote.sh auto` (dream step 4b) stages confidence-≥0.8 entries into `~/.claude/memory/instincts/global.yml` as `status: candidate` with project provenance. When a **second distinct project** promotes the same trigger, the entry flips to `status: global`. Global instincts apply across all projects.

## Hard rules

- **Project by default.** Never auto-write to `~/.claude/instincts/global.yml` without the 2-project threshold.
- **Confidence-gated.** Instincts with confidence <0.5 are advisory only (not injected as system-reminders, only logged).
- **Reinforce, don't duplicate.** A repeat observation of an existing instinct increments `reinforced` and updates `last_seen`; doesn't create a new entry.
- **PII-clean observations.** Strip file paths to relative; strip URLs to domain; never log Bash stdout content (only exit codes + error class).
- **Decay.** Instincts not reinforced in 60 days drop confidence by 0.1; under 0.3 they archive.

## Manual commands

- `/instinct list` — show active instincts sorted by confidence
- `/instinct extract` — force an extraction pass now
- `/instinct promote <id>` — manually promote project → global
- `/instinct promote <id> --as-skill` — **Round 9 A**: when reinforced ≥ 10, materialize the instinct as a proposed skill via skill-creator. Writes to `.claude/memory.proposed/skills/<slug>/`; activate via `/dream-review --approve-skill <slug>`. Closes Round 5's "instinct → skill" loop.
- `/instinct archive <id>` — soft-delete (kept in archive.yml)

## References

- affaan-m/ECC/skills/continuous-learning-v2 (source — observer + Haiku extractor)
- Anthropic Memory Tool (parallel: per-task scratchpads in `/memories/`)
- The "lessons learned" pattern in `.claude/memory/incidents/` (handwritten; instincts are the auto-extracted complement)
