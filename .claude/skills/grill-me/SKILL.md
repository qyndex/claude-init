---
name: grill-me
description: Use when authoring an initiative, clarifying interdependent open questions, or designing a multi-quarter roadmap — depth-first one-at-a-time interrogation with agent recommendation + reasoning per question. Skip for bug-fix / implement / verify (too much friction).
when_to_use: When authoring an initiative or clarifying ≥3 interdependent open questions; depth-first one-at-a-time interrogation with agent recommendation per question.
model: sonnet
disable-model-invocation: false
---

# Grill me

> Vendored from [mattpocock/skills/skills/productivity/grill-me](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) (commit `bd04394c`). House-extended with recommendation format, codebase exploration policy, complexity gate, and AUTOPILOT bailout.

## When to invoke

Auto-on:
- `/initiative create` (every initiative, regardless of size)
- `/specify` for specs with `complexity: L` or `complexity: XL`
- `/clarify` when ≥3 `[OQ]` items cluster around one subsystem (interdependent)
- `/okrs` (when defining new KRs — they cascade)
- `/roadmap` (Now/Next/Later cuts — prioritisation cascades)

Hard-exclude (do NOT grill):
- Bug-fix / `/debug` / `/implement` / `/verify` — interrogation is too late
- Trivial specs (`complexity: S`) — batched questions are faster
- Refactors that don't change architecture
- Anything in `[autopilot]` / Cloud Routine / `--bg` context (no human to answer — use recommendations as defaults instead; log open questions in handoff)

## The core directive

Interview the operator relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

**For each question**:
1. Pose ONE question (never batch — one at a time)
2. Provide YOUR recommended answer
3. Give 3-4 multiple-choice alternatives
4. Explain WHY you recommend the option you did, in one sentence

**If a question can be answered by exploring the codebase, explore the codebase instead.** Never ask the operator "what does X do" when grep can tell you in 10 seconds.

## House format

Use `AskUserQuestion` with the `header` field. Format:

```
Q<N>: <one specific decision-forcing question>

  Recommended: <option you'd pick>
    Why: <one sentence reasoning — cite codebase evidence where possible>

  Other options:
    (a) <alt 1>
    (b) <alt 2>
    (c) <alt 3>
```

Pass the recommendation as the FIRST option in the `options` array (with "(Recommended)" in the label).

## Branch-walking discipline

Ask in dependency order. If Q2's answer depends on Q1, ask Q1 first. The mental model is a directed acyclic graph; you walk depth-first.

When you sense the operator is uncertain, ask a meta-question:
- "Should I keep grilling, or would you rather defer the rest to /clarify later?"
- "I have ~5 more questions in this branch. Continue, or stop here and let the rest emerge from prototyping?"

## AUTOPILOT bailout

When running in unattended context (`AUTOPILOT=1`, Cloud Routine, `claude --bg`, `claude -p`):

1. Do NOT call `AskUserQuestion`.
2. For each question that would be asked, write the recommended answer to a draft, with confidence: high|tentative.
3. Append the question + recommendation to `[OQ-pending-operator-review]` items in the spec/initiative.
4. Tag the artifact with `status: draft-autopilot-needs-review` (not `approved`).
5. Surface the count of unresolved Qs in the handoff (`OVERNIGHT_REPORT.md` or stream NEXUS handoff).

Never block on a human in autopilot. Never auto-approve as if the human answered.

## Closing the grill

When the design tree is exhausted (no more questions whose answers materially shape the artifact), stop. Don't ask filler questions to seem thorough.

Output a one-line confirmation:
> "Grilled. Drafting <spec/plan/initiative> now."

Then proceed.

## Hard rules

- One question per turn. Never batch.
- Always provide a recommendation. "What do you think?" is not grilling.
- Always provide reasoning. The operator should learn from the recommendation even when they override it.
- Cite the codebase when possible — grep is free, operator time is not.
- Don't grill beyond the depth that materially affects the artifact. Stop when stopping.
- Confidence: high for high-stakes branches, tentative for nice-to-have details. Make it explicit so the operator knows where to apply scrutiny.

## Attribution

Original: [mattpocock/skills](https://github.com/mattpocock/skills) — `skills/productivity/grill-me/SKILL.md` at commit `bd04394c675ee54173a093c50eb74da01a2940fa`. MIT-licensed.

House extensions (recommendation format, complexity gate, AUTOPILOT bailout, codebase-exploration substitution) are project-specific to this harness.
