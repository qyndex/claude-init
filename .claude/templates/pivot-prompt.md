# Pivot prompt — researcher subagent

> Injected by `loop-iteration.sh` when a task aborts for the **second consecutive
> time**. The current approach is stuck; the job is to find a _different_ one,
> not to retry the same path harder.

## Context (filled in by the loop)

- **Task:** `{{TASK_ID}}` — {{TASK_SUMMARY}}
- **Spec / acceptance:** {{SPEC_REF}}
- **Failed approach (attempt 1):** {{ATTEMPT_1_SUMMARY}}
- **Failed approach (attempt 2):** {{ATTEMPT_2_SUMMARY}}
- **Observed error signature:** {{ERROR_HASH}} — {{ERROR_EXCERPT}}

## Your job

The same task has aborted twice in a row. Do **not** propose a third variation of
the approach that already failed. Step back and find a genuinely different route to
the same acceptance criterion.

1. Diagnose _why_ the prior approaches failed — state the root cause in one sentence.
2. Generate **at most 2** alternative approaches that attack the problem differently
   (different algorithm, different layer, different tool, or reframing the task).
3. For each, note the key trade-off and the fastest way to validate it.
4. If you believe the task is mis-specified or genuinely blocked (not just hard),
   say so explicitly — a pivot to "escalate to human" is a valid alternative.

## Required output

End your response with a fenced block in exactly this shape (1 or 2 alternatives):

```
<alternative approach>
  rank: 1
  approach: <one-line description of the different route>
  why-different: <how it avoids the prior failure's root cause>
  validate-with: <the fastest check that proves it works>
  trade-off: <what this costs vs. the original approach>
</alternative approach>
```

Keep it tight. The loop will pick rank 1 and re-attempt the task with that approach;
rank 2 is the fallback. If no viable alternative exists, return a single block with
`approach: escalate-to-human` and `why-different: <why no automated path remains>`.
