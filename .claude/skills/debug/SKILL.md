---
name: debug
description: Run the four-phase systematic debugging loop (reproduce → isolate → diagnose → fix). Delegates to debugger agent. Modeled on superpowers/systematic-debugging.
when_to_use: A test fails unexpectedly, the app crashes, behavior diverges from expected, an error message is unclear, or the user says "debug", "what's wrong", "why does this fail".
argument-hint: "<symptom, error message, or failing test path>"
model: opus
allowed-tools: Read, Glob, Grep, Bash, WebSearch, WebFetch
context: fork
agent: debugger
---

# Debug

Find the root cause. Don't paper over symptoms.

## Four-phase loop

### Phase 1 — Reproduce
Make the bug happen reliably. Capture:
- Exact command
- Exact input
- Environment (node/python/etc. version, OS, env vars)
- Stdout, stderr, exit code

If you can't reproduce in three tries, ask the user for the missing detail. Don't hope.

### Phase 2 — Isolate
Bisect to the minimal reproducer:
- `git bisect` if it worked at some prior commit
- Strip inputs to the smallest case that still triggers
- Disable unrelated code paths

### Phase 3 — Diagnose
Trace the actual code path. Form a hypothesis. Test it. Iterate.

A hypothesis is valid only when it explains **every** observed symptom — not just some.

### Phase 4 — Fix proposal
Smallest correct change. Cite the file:line. Hand off to implementer.

## Hard rules

- **Don't fix without understanding.** A fix you can't explain regresses.
- **Don't suppress.** No `try/except: pass`, no `// @ts-ignore`, no broad `catch {}`.
- **Don't blame infra.** Until proven otherwise, assume it's your code.
- **Cite the line.** `src/auth/login.ts:42` is specific. "The auth code" is not.
- **No commits.** Debugger proposes; implementer commits.

## Output

```
# Bug: <one-line title>

## Reproduction
Command: ...
Env: ...
Output: ...

## Cause
File: <path:line>
Issue: <what is wrong, why it triggers, how it explains every symptom>

## Fix proposal
File: <path>
Change: <minimal diff intent>
Why: <how this addresses the cause>
Test: <command to verify>

## Hand-off
implementer agent: apply the fix, run the test, then the full suite.
```
