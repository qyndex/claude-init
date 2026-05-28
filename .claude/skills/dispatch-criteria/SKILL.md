---
name: dispatch-criteria
description: Six gates for deciding whether to delegate to a subagent or do it in-session. From ChristopherKahler/paul. The "is this work parallelizable" decision aid.
when_to_use: About to spawn a subagent (Task/Agent tool). About to dispatch parallel agents. Considering /loop. User asks "should I do this in parallel".
model: inherit
---

# Dispatch Criteria — Six Gates

Subagents are not free. Spawning one costs startup tokens, adds latency, and burns a context window. Use this checklist **before** every `Task`/`Agent` invocation.

## The six gates

1. **Independence**
   - Does the subtask share *mutable* state with the main task?
   - Does it need to wait for in-flight edits to settle?
   - If yes to either → **don't delegate** (sequential in main session).

2. **Clear scope**
   - Can you write the brief in one paragraph?
   - Does the subagent know exactly which files / endpoints / questions are in scope?
   - If no → **sharpen the brief first**, then decide.

3. **Parallel value**
   - Will running it in parallel save wall-clock time (>30s)?
   - Will it save tokens by isolating heavy reads?
   - If both no → **don't delegate** (overhead exceeds value).

4. **Complexity sweet spot**
   - Too simple (a regex or one `grep` would do) → **don't delegate**.
   - Too complex (would need its own multi-day session) → **don't delegate**, decompose first.
   - Sweet spot: 5-30 min of subagent work, single-purpose outcome.

5. **Token efficiency**
   - Would the work in main context cost >20K tokens of reads/searches/fetches?
   - Is the output a clean summary that fits in <2K tokens?
   - If both yes → **delegate** (this is the strongest signal).

6. **State compatibility**
   - Is the subagent's output a markdown summary, JSON, or list?
   - Or does it need to leave in-flight, half-applied edits in the working tree?
   - If half-edits → **don't delegate** (no merge mechanism).

## Decision matrix

Count gates passed (out of 6):
- **6/6** → delegate
- **5/6** → delegate, but tighten the brief on the failing gate
- **4/6** → marginal — try if you're context-pressured, otherwise in-session
- **≤3/6** → don't delegate. Do it yourself, or decompose first.

## When in doubt

Default to **in-session** for code edits, **delegate** for read-heavy investigation/research/review.

## References

- ChristopherKahler/paul/src/references/subagent-criteria.md (source)
- obra/superpowers/skills/dispatching-parallel-agents (parallel = N independent investigations, never N parallel edits)
- obra/superpowers/skills/subagent-driven-development (single sequential subagent per task with two-stage review)
